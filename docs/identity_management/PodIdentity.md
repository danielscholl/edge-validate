# Instructions for Testing Pod Identity using flux

Install AAD Pod Identity using

```bash
cat > ./clusters/$AKS_NAME/aad-pod-identity.yaml <<EOF
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

# Update the Git Repo
git add ./clusters/$AKS_NAME/aad-pod-identity.yaml && git commit -m "Installing AAD Pod Identity" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl -n aad-pod-identity get pods
```

Create the Identity and Binding

```bash
POD_IDENTITY_NAME="kv-access-identity"
RESOURCE_GROUP="azure-k8s"
AKS_NAME="azure-k8s"

# Retrieve Required Identity Values
POD_IDENTITY_CLIENT_ID=$(az identity show -n $POD_IDENTITY_NAME -g $RESOURCE_GROUP -o tsv --query "clientId")
POD_IDENTITY_ID=$(az identity show -n $POD_IDENTITY_NAME -g $RESOURCE_GROUP -o tsv --query "id")

# Create or Update the AzureIdentity and Binding
cat > ./clusters/$AKS_NAME/sops-identity.yaml <<EOF
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentity
metadata:
  name: sops-akv-decryptor
  namespace: flux-system
spec:
  clientID: $POD_IDENTITY_CLIENT_ID
  resourceID: $POD_IDENTITY_ID
  type: 0 # user-managed identity
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentityBinding
metadata:
  name: sops-akv-decryptor-binding
  namespace: flux-system
spec:
  azureIdentity: sops-akv-decryptor
  selector: sops-akv-decryptor
EOF

# Update the Git Repo to deploy
git add ./clusters/$AKS_NAME/sops-identity.yaml && git commit -m "Updated Identity and Binding" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl -n flux-system describe AzureIdentity
```
