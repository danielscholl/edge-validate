# Instructions for Testing Pod Identity

```bash
RESOURCE_GROUP="azure-k8s"
AKS_NAME="azure-k8s"
LOCATION="eastus"

# Get Kubelet Identity
RESOURCE_GROUP_ID=$(az group show -n $RESOURCE_GROUP -o tsv --query id)
AKS_RESOURCE_GROUP_NAME=$(az aks show -g $RESOURCE_GROUP -n $AKS_NAME -o tsv --query nodeResourceGroup)
AKS_RESOURCE_GROUP_ID=$(az group show -n $RESOURCE_GROUP -o tsv --query id)
KUBELET_CLIENT_ID=$(az aks show -g $RESOURCE_GROUP -n $AKS_NAME -o tsv --query identityProfile.kubeletidentity.clientId)

# Assign Roles to Kubelet Identity
az role assignment create --role "Virtual Machine Contributor" --assignee $KUBELET_CLIENT_ID --scope $AKS_RESOURCE_GROUP_ID
az role assignment create --role "Managed Identity Operator" --assignee $KUBELET_CLIENT_ID --scope $RESOURCE_GROUP_ID

```

Install AAD Pod Identity using a Flux Manifest

```bash
cat > ./manifests/aad-pod-identity.yaml <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: aad-pod-identity
---
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
      version: 4.0.0
      sourceRef:
        kind: HelmRepository
        name: aad-pod-identity
        namespace: aad-pod-identity
      interval: 1m
  values:
    nmi:
      allowNetworkPluginKubenet: true
EOF

```