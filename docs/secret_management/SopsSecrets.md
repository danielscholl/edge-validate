# Instructions for SOPS Secrets

> This activity requires Key Vault.

**Install Mozilla SOP on the Azure Kubernetes Instance**

Patch the kustomize-controller Pod template to match the AzureIdentity name label and allow binding.

```bash
RESOURCE_GROUP="azure-k8s"
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME

# Retrieve KV Identity Information
KV_IDENTITY_NAME="kv-access-identity"
KV_IDENTITY_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${KV_IDENTITY_NAME} --query id -otsv)"
KV_IDENTITY_CLIENT_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${KV_IDENTITY_NAME} --query clientId -otsv)"
KUBENET_ID="$(az aks show -g ${RESOURCE_GROUP} -n ${AKS_NAME} --query identityProfile.kubeletidentity.clientId -otsv)"

# Create a KV Sops Identity
cat > ./clusters/$AKS_NAME/sops-identity.yaml <<EOF
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
git add ./clusters/$AKS_NAME && git commit -m "SOPS Configuration" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl describe Kustomization flux-system -n flux-system
```

Create a .sops.yaml

```bash
VAULT_NAME="azure-k8s-vault"

# Retrieve the Key ID
KEY_URL=$(az keyvault key show --name sops-key --vault-name $VAULT_NAME --query key.kid -otsv)

cat <<EOF > ./clusters/$AKS_NAME/.sops.yaml
creation_rules:
  - path_regex: .*.yaml
    encrypted_regex: ^(data|stringData)$
    azure_keyvault: $KEY_URL
EOF

git add -f ./clusters/$AKS_NAME/.sops.* && git commit -am "Save sops file for secrets generation" && git push
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
```


**Install Sealed Secrets on the ARC Enabled Kubernetes Instance**
```bash
ARC_AKS_NAME="kind-k8s"
kubectl config use-context "kind-$ARC_AKS_NAME"

# Generate a GPG/OpenPGP key with no passphrase
KEY_NAME="edge.microsoft.com"
KEY_COMMENT="flux secrets"

gpg --batch --full-generate-key <<EOF
%no-protection
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Expire-Date: 0
Name-Comment: ${KEY_COMMENT}
Name-Real: ${KEY_NAME}
EOF

# Retrieve the GPG key fingerprint
KEY_FP=$(gpg --list-secret-keys "${KEY_NAME}" | head -2 | tail -1 | sed 's/^ *//g')

# Create a Kubernetes secret named sops-gpg in the flux-system namespace
# This key might want to be backed up in some secure place in case it gets deleted.
gpg --export-secret-keys --armor "${KEY_FP}" | \
kubectl create secret generic sops-gpg \
  --namespace=flux-system \
  --from-file=sops.asc=/dev/stdin

# Save the Public Key to Git and a SOPS Config file
gpg --export --armor "${KEY_FP}" > ./clusters/$ARC_AKS_NAME/.sops.pub.asc

cat <<EOF > ./clusters/$ARC_AKS_NAME/.sops.yaml
creation_rules:
  - path_regex: .*.yaml
    encrypted_regex: ^(data|stringData)$
    pgp: ${KEY_FP}
EOF

git add -f ./clusters/$ARC_AKS_NAME/.sops.* && git commit -am "Share GPG public key for secrets generation" && git push

# Delete the key from machine
gpg --delete-secret-keys "${KEY_FP}"

# Import the Key for encrypting
gpg --import ./clusters/$ARC_AKS_NAME/.sops.pub.asc

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
sops --encrypt --config ./clusters/$ARC_AKS_NAME/.sops.yaml secret.yaml > ./sops-secret-enc.yaml && rm secret.yaml
kubectl apply -f ./sops-secret-enc.yaml --validate=false && rm sops-secret-enc.yaml

# Deploy and Validate Secret
kubectl describe secret sops-secret-credentials
```
