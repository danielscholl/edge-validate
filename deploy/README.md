# Install Instructions

## Create a Cluster

```bash
CLUSTER="dev"

# Setup a Cluster likeAKS with Calico as Network Plugin with IngressPort = 30000,300001
cat <<EOF | kind create cluster --name=$CLUSTER --config=-
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
networking:
  apiServerAddress: "127.0.0.1"
  apiServerPort: 6443
  podSubnet: "10.240.0.0/16"
  serviceSubnet: "10.0.0.0/16"
  disableDefaultCNI: true
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    listenAddress: "127.0.0.1"
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    listenAddress: "127.0.0.1"
    protocol: TCP
EOF

# Install Calico Networking and NGINX Ingress Controller
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml && \
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml


# Scale down CoreDNS to save resources
kubectl scale deployment --replicas 1 coredns --namespace kube-system

# Validate the Node is Ready
kubectl get nodes -w
```

## Configure the Cluster

```bash
#########################
### CONFIGURE CLUSTER ###
#########################
GITHUB_TOKEN="<your-github-token>"
GITHUB_REPO="<your-github-project>"
GITHUB_USER="<your-github-organization>"

# Bootstrap Flux Components
flux bootstrap github --owner=$GITHUB_USER --repository=$GITHUB_REPO --branch=main --path=./clusters/$CLUSTER

# Clone the Repo
git clone git@github.com:$GITHUB_USER/$GITHUB_REPO.git flux-infra

# Create the Edge Validate Git Source
flux create source git edge-validate \
  --url https://github.com/danielscholl/edge-validate \
  --interval 1m \
  --branch main \
  --export > flux-infra/clusters/$CLUSTER/edge-infra-source.yaml

# Create the Edge Validate Kustomization
flux create kustomization edge-infra \
  --source=edge-validate \
  --path=./deploy/manifests \
  --prune=true \
  --interval=5m \
  --export > flux-infra/clusters/$CLUSTER/edge-infra-kustomization.yaml

# Update the Git Repo
BASE_DIR=$(pwd)
cd flux-infra && \
  git add -f clusters/$CLUSTER/edge-infra-*.yaml && \
  git commit -am "Configuring Edge-Infra Deployments" && \
  git push && \
  cd $BASE_DIR

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get HelmRelease -A -w
kubectl get pods -n istio-system
kubectl get pods -n istio-operator
```

## Deploy a Sample Application

Create required Azure Resources

```bash
RESOURCE_GROUP="validate-sample"
LOCATION="eastus"
RAND="$(echo $RANDOM | tr '[0-9]' '[a-z]')"
VAULT_NAME="kv-$RAND"
PRINCIPAL_NAME="principal-$RAND"
TENANT_ID=$(az account show --query tenantId -otsv)
SUBSCRIPTION_ID=$(az account show --query id -otsv)

# Create a Resource Group
az group create -n $RESOURCE_GROUP -l $LOCATION

# Create Key Vault
az keyvault create --name $VAULT_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

# Create a Secret
SECRET_NAME="admin"
SECRET_VALUE="t0p-S3cr3t"
az keyvault secret set --name $SECRET_NAME --value $SECRET_VALUE --vault-name $VAULT_NAME

# Create a Service Principal for validation
PRINCIPAL_SECRET=$(az ad sp create-for-rbac -n $PRINCIPAL_NAME --skip-assignment --query password -o tsv)
PRINCIPAL_ID=$(az ad sp list --display-name $PRINCIPAL_NAME --query [].appId -o tsv)
PRINCIPAL_OID=$(az ad sp list --display-name $PRINCIPAL_NAME --query [].objectId -o tsv)

# Provide Access to the Service Principal
az keyvault set-policy --name $VAULT_NAME --resource-group $RESOURCE_GROUP --object-id $PRINCIPAL_OID --key-permissions encrypt decrypt --secret-permissions get --certificate-permissions get
```

Deploy Application to Kubernetes

```bash
# Create the Application Base Resources
mkdir -p flux-infra/apps/base/sample-app



cat > flux-infra/apps/base/sample-app/release.yaml <<EOF
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: environment-debug
  namespace: sample-app
spec:
  chart:
    spec:
      chart: ./charts/env-debug
      sourceRef:
        kind: GitRepository
        name: edge-validate
        namespace: flux-system
  interval: 5m0s
  install:
    remediation:
      retries: 3
  targetNamespace: sample-app
  values:
    message: "Sample App"
EOF

cat > flux-infra/apps/base/sample-app/kustomization.yaml <<EOF
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: sample-app
resources:
  - release.yaml
EOF

# Create the Application Environment Overrides or Patches
mkdir -p flux-infra/apps/$CLUSTER

cat > flux-infra/apps/$CLUSTER/namespace.yaml <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: sample-app
EOF

kubectl create secret generic kv-creds \
  --namespace sample-app \
  --from-literal clientsecret=$PRINCIPAL_SECRET --dry-run=client -o yaml| kubeseal \
    --controller-namespace kube-system \
    --controller-name sealed-secrets \
    --format yaml > flux-infra/apps/$CLUSTER/sample-app-secret.yaml

cat > flux-infra/apps/$CLUSTER/sample-app-values.yaml <<EOF
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: environment-debug
  namespace: sample-app
spec:
  values:
    message: "Environment is $CLUSTER"
    azure:
      tenant_id: $TENANT_ID
      subscription_id: $SUBSCRIPTION_ID
      keyvault_name: $VAULT_NAME
EOF

cat > flux-infra/apps/$CLUSTER/kustomization.yaml <<EOF
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: sample-app
resources:
  - namespace.yaml
  - sample-app-secret.yaml
  - ../base/sample-app
patchesStrategicMerge:
  - sample-app-values.yaml
EOF


# Update the Git Repo
BASE_DIR=$(pwd)
cd flux-infra && \
  git add -f apps/base && \
  git add -f apps/$CLUSTER && \
  git commit -am "Sample App Deployment" && \
  git push && \
  cd $BASE_DIR


#####################################
### Deploy the Apps Kustomization ###
#####################################
flux create kustomization edge-apps \
  --source=flux-system \
  --path=./apps/$CLUSTER \
  --prune=true \
  --interval=5m \
  --depends-on=edge-infra \
  --export > flux-infra/clusters/$CLUSTER/edge-apps-kustomization.yaml

# Update the Git Repo
BASE_DIR=$(pwd)
cd flux-infra && \
  git add -f clusters/$CLUSTER/edge-apps-kustomization.yaml && \
  git commit -am "Hookup Apps Kustomization" && \
  git push && \
  cd $BASE_DIR

# Validate the kustomization
flux reconcile kustomization flux-system --with-source
flux get kustomizations
```

## Cleanup *(optional)*

```bash
BASE_DIR=$(pwd)

# Remove the KinD Cluster Cluster Configuration, Apps and Cloned Repo
kind delete cluster --name $CLUSTER && \
rm -rf flux-infra/clusters && rm -rf flux-infra/apps && \
cd flux-infra && \
  git add -f clusters && \
  git add -f apps && \
  git commit -am "Removing Cluster" && \
  git push && \
  cd $BASE_DIR && \
rm -rf flux-infra
```
