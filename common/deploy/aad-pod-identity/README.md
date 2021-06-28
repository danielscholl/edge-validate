# Validation: Pod Identity on Kind Cluster

This validation is to simplify the kind pod identity cluster validation effort.


```bash
# Using kind create a Kubernetes Cluster
ARC_AKS_NAME="kind-k8s"
kind create cluster --name $ARC_AKS_NAME

################################
### Setup and Configure Flux ###
################################

# Setup Values for Github Access
export GITHUB_TOKEN=<your-token>
export GITHUB_USER=<your-username>
export GITHUB_REPO=<your-repo>

flux check --pre
flux bootstrap github \
    --context=kind-${ARC_AKS_NAME} \
    --owner=${GITHUB_USER} \
    --repository=${GITHUB_REPO} \
    --branch=main \
    --personal \
    --path=clusters/${ARC_AKS_NAME}


##############################
### Install Sealed Secrets ###
##############################
cat <<EOF | kubectl apply --namespace default -f -
apiVersion: v1
kind: Namespace
metadata:
  name: sealed-secrets
EOF

# Create a Flux Helm Source
flux create source helm sealed-secrets \
  --url https://bitnami-labs.github.io/sealed-secrets \
  --interval 1m

# Create a Flux Helm Repo
flux create helmrelease sealed-secrets \
    --interval=1m \
    --release-name=sealed-secrets \
    --target-namespace=sealed-secrets \
    --source=HelmRepository/sealed-secrets \
    --chart=sealed-secrets \
    --chart-version=">=1.16.0-0" \
    --crds=CreateReplace


########################
### AAD POD IDENTITY ###
########################

# Create a Service Principal
IDENTITY_CLIENT_SECRET=$(az ad sp create-for-rbac -n $ARC_AKS_NAME --role contributor --query password -o tsv)
IDENTITY_CLIENT_ID=$(az ad sp list --display-name $ARC_AKS_NAME --query [].appId -o tsv)
TENANT_ID=$(az account show --query homeTenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)





# Create Namespace
cat <<EOF | kubectl apply --namespace default -f -
apiVersion: v1
kind: Namespace
metadata:
  name: aad-pod-identity
EOF

# Create a Sealed Secret for AAD Pod Identity
cat <<EOF | kubeseal \
    --controller-namespace sealed-secrets  \
    --controller-name sealed-secrets \
    --format yaml | \
    kubectl apply --namespace aad-pod-identity -f -
---
apiVersion: v1
data:
  Cloud: $(echo "AzureCloud" | base64)
  SubscriptionID: $(echo -n $SUBSCRIPTION_ID | base64)
  ResourceGroup: $(echo $ARC_AKS_NAME |base64)
  VMType: $(echo "Standard" | base64)
  TenantID: $(echo -n $TENANT_ID | base64)
  ClientID: $(echo -n $IDENTITY_CLIENT_ID | base64)
  ClientSecret: $(echo -n $IDENTITY_CLIENT_SECRET | base64)
kind: Secret
metadata:
  name: aadpodidentity-admin-secret
  namespace: aad-pod-identity
EOF

# Validate Secret Exists
kubectl describe Secret aadpodidentity-admin-secret -n aad-pod-identity

# Create a Flux Git Source
flux create source git aad-pod-identity \
  --url https://github.com/danielscholl/edge-validate \
  --branch main \
  --interval 1m \
  --namespace=aad-pod-identity

flux create kustomization aad-pod-identity \
    --source=GitRepository/aad-pod-identity \
    --path="./common/deploy/aad-pod-identity" \
    --prune=true \
    --interval=5m \
    --namespace=aad-pod-identity \
    --target-namespace=aad-pod-identity

# Validate Secret Exists
kubectl get pods -n aad-pod-identity
