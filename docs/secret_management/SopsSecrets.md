# Instructions for Setting up Key Vault

Create a Key Vault with a User Managed Identity the access policy and the Azure Identity


Patch the kustomize-controller Pod template to match the AzureIdentity name label and allow binding.

```bash
KV_IDENTITY_NAME="kv-access-identity"
KV_IDENTITY_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${KV_IDENTITY_NAME} --query id -otsv)"
KV_IDENTITY_CLIENT_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${KV_IDENTITY_NAME} --query clientId -otsv)"
KUBENET_ID="$(az aks show -g ${RESOURCE_GROUP} -n ${AKS_NAME} --query identityProfile.kubeletidentity.clientId -otsv)"

# Create a KV Sops Identity
cat <<EOF | kubectl apply --namespace default -f -
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentity
metadata:
  name: sops-access-identity
  namespace: default
spec:
  clientID: $KV_IDENTITY_CLIENT_ID
  resourceID: $KV_IDENTITY_ID
  type: 0 # user-managed identity
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentityBinding
metadata:
  name: sops-access-identity-binding
  namespace: default
spec:
  azureIdentity: sops-access-identity
  selector: sops-akv-decryptor
EOF

# Create the Patch
cat > ./clusters/$AKS_NAME/flux-system/gotk-patches.yaml <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kustomize-controller
  namespace: flux-system
spec:
  template:
    metadata:
      labels:
        aadpodidbinding: sops-akv-decryptor  # match the AzureIdentityBinding selector
    spec:
      containers:
      - name: manager
        env:
        - name: AZURE_AUTH_METHOD
          value: msi
EOF

# Update Kustomization
cat > ./clusters/$AKS_NAME/flux-system/kustomization.yaml <<EOF
---
kind: Kustomization
resources:
  - gotk-components.yaml
  - gotk-sync.yaml
patchesStrategicMerge:
  - gotk-patches.yaml
EOF

# Update the Git Repo to deploy
git add ./clusters/$AKS_NAME/flux-system && git commit -m "SOPS Configuration" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl describe Kustomization flux-system -n flux-system
```

Create a local .sops.yaml

```bash
VAULT_NAME="azure-k8s-vault"

# Retrieve the Key ID
KEY_URL=$(az keyvault key show --name sops-key --vault-name $VAULT_NAME --query key.kid -otsv)

cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: .*.yaml
    encrypted_regex: ^(data|stringData)$
    azure_keyvault: $KEY_URL
EOF
```

Create a secret

```bash
VAULT_NAME="azure-k8s-vault"
RESOURCE_GROUP="azure-k8s"
AKS_NAME="azure-k8s"

# Ensure signed in user can encrypt and decrypt
OID=$(az ad signed-in-user show -o tsv --query objectId)
az keyvault set-policy --name $VAULT_NAME --resource-group $RESOURCE_GROUP --object-id $OID --key-permissions encrypt decrypt

# Create a temporary Secret
cat > ./secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: sops-secret-credentials
  namespace: default
type: Opaque
stringData:
  username: admin
  password: t0p-S3cr3t
EOF

# Encrypt a Secret
sops --encrypt secret.yaml > ./sops-secret-enc.yaml && rm secret.yaml
kubectl apply -f ./sops-secret-enc.yaml --validate=false && rm sops-secret-enc.yaml

# Deploy and Validate Secret
kubectl describe secret sops-secret-credentials