# Validation: Pod Identity on Kind Cluster

This validation is to simplify the kind pod identity cluster validation effort.

https://github.com/Azure/aad-pod-identity/issues/970



```bash
# Using kind create a Kubernetes Cluster
ARC_AKS_NAME="kind-k8s"
kind create cluster --name $ARC_AKS_NAME

# Arc Enable the Cluster
az connectedk8s connect -n $ARC_AKS_NAME -g $RESOURCE_GROUP

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
  TenantID: $(echo -n $TENANT_ID | base64)
  ClientID: $(echo -n $IDENTITY_CLIENT_ID | base64)
  ClientSecret: $(echo -n $IDENTITY_CLIENT_SECRET | base64)
kind: Secret
metadata:
  name: adminsecret
  namespace: aad-pod-identity
EOF

# Validate the Secret Exists
kubectl describe Secret adminsecret -n aad-pod-identity


cat <<EOF | kubectl apply --namespace aad-pod-identity -f -
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: HelmRepository
metadata:
  name: aad-pod-identity
  namespace: aad-pod-identity
spec:
  url: https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
  interval: 10m
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: aad-pod-identity
  namespace: aad-pod-identity
spec:
  interval: 5m
  chart:
    spec:
      chart: aad-pod-identity
      version: 4.1.1
      sourceRef:
        kind: HelmRepository
        name: aad-pod-identity
        namespace: aad-pod-identity
      interval: 1m
  values:
    operationMode: managed
  valuesFrom:
  - kind: Secret
    name: adminsecret
    valuesKey: TenantID
    targetPath: adminsecret.TenantID
  - kind: Secret
    name: adminsecret
    valuesKey: ClientID
    targetPath: adminsecret.ClientID
  - kind: Secret
    name: adminsecret
    valuesKey: ClientSecret
    targetPath: adminsecret.ClientSecret
EOF

# Validate Secret Exists
kubectl get helmrelease -A
kubectl get pods -n aad-pod-identity
```


```bash
RESOURCE_GROUP="azure-k8s"
IDENTITY="test-identity"

# Create a test Managed Identity
az identity create --resource-group $RESOURCE_GROUP --name $IDENTITY

# Assign a Role
POD_IDENTITY_ID="$(az identity show -g $RESOURCE_GROUP -n $IDENTITY --query id -otsv)"
POD_IDENTITY_CLIENT_ID="$(az identity show -g $RESOURCE_GROUP -n $IDENTITY --query clientId -otsv)"
az role assignment create --role "Managed Identity Operator" --assignee "$IDENTITY_CLIENT_ID" --scope $POD_IDENTITY_ID


# Create the AzureIdentity and Binding and deploy a test pod
cat <<EOF | kubectl apply --namespace default -f -
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentity
metadata:
  name: test-identity
  namespace: default
spec:
  type: 0
  resourceID: $POD_IDENTITY_ID
  clientID: $POD_IDENTITY_CLIENT_ID
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentityBinding
metadata:
  name: test-identity-binding
  namespace: default
spec:
  azureIdentity: test-identity
  selector: test-identity
---
apiVersion: v1
kind: Pod
metadata:
  name: identity-test
  labels:
    aadpodidbinding: test-identity
spec:
  containers:
  - name: identity-test
    image: mcr.microsoft.com/oss/azure/aad-pod-identity/demo:v1.6.3
    args:
      - --subscriptionid=$(az account show --query id -otsv)
      - --clientid=${POD_IDENTITY_CLIENT_ID}
      - --resourcegroup=${RESOURCE_GROUP}
    env:
      - name: MY_POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: MY_POD_NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: MY_POD_IP
        valueFrom:
          fieldRef:
            fieldPath: status.podIP
  nodeSelector:
    kubernetes.io/os: linux
EOF
```
