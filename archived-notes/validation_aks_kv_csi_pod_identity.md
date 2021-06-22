# Validation: AKS - Preview features KV CSI Secret Driver with Pod Identity

This validation for AKS will use managed Pod Identies and Managed Key Vault CSI Secret Driver features built into AKS to test secret management with Key Vault Secrets.


Ensure the Subscription is prepared for Preview Features.

```bash
# Azure CLI Login
az login
az account set --subscription <your_subscription>

# Enable Preview Features (one time action)
az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
az feature register --namespace Microsoft.ContainerService --name AKS-AzureKeyVaultSecretsProvider
az feature show --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
az feature show --name AKS-AzureKeyVaultSecretsProvider --namespace Microsoft.ContainerService

# Register Providers (one time action)
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ExtendedLocation
az provider register --namespace Microsoft.ContainerService

# Show Providers  (one time action)
az provider show -n Microsoft.Kubernetes -o table
az provider show -n Microsoft.KubernetesConfiguration -o table
az provider show -n Microsoft.ExtendedLocation -o table

# Add CLI Extensions
az extension add --name aks-preview
az extension add --name connectedk8s
az extension add --name k8s-configuration
az extension add --name k8s-extension
az extension add --name customlocation
```

Setup AKS Cluster

```bash
RESOURCE_GROUP="azure-k8s"
LOCATION="eastus"

# Create a Resource Group
az group create -n $RESOURCE_GROUP -l $LOCATION

# Create a Control Plane Identity
IDENTITY_NAME="aks-controlplane-identity"
az identity create -n $IDENTITY_NAME -g $RESOURCE_GROUP -l $LOCATION
IDENTITY_ID=$(az identity show -n $IDENTITY_NAME -g $RESOURCE_GROUP -o tsv --query "id")

# Create a Cluster using Managed Identity
AKS_NAME="azure-k8s"
az aks create -g $RESOURCE_GROUP -n $AKS_NAME \
    --network-plugin azure \
    --enable-managed-identity  \
    --assign-identity $IDENTITY_ID \
    --generate-ssh-keys

# Get the Credentials
az aks get-credentials -g $RESOURCE_GROUP -n $AKS_NAME

# Validate the Cluster
kubectl cluster-info --context $AKS_NAME

# Install AAD Pod Identity
az aks update --name $AKS_NAME --resource-group $RESOURCE_GROUP --enable-pod-identity

# Validate the Install
kubectl describe daemonset nmi -n kube-system

# Install Azure CSI Driver with auto Key Rotation
az aks enable-addons --addons azure-keyvault-secrets-provider --name $AKS_NAME --resource-group $RESOURCE_GROUP
az aks update --name $AKS_NAME --resource-group $RESOURCE_GROUP --enable-secret-rotation

# Validate the Install
kubectl get pods -n kube-system -l 'app in (secrets-store-csi-driver, secrets-store-provider-azure)'

# Assign Kubelet Required Roles required for AAD Pod Identity
KUBENET_ID="$(az aks show -g ${RESOURCE_GROUP} -n ${AKS_NAME} --query identityProfile.kubeletidentity.clientId -otsv)"
NODE_GROUP=$(az aks show -g ${RESOURCE_GROUP} -n $AKS_NAME --query nodeResourceGroup -o tsv)
NODES_RESOURCE_ID=$(az group show -n $NODE_GROUP -o tsv --query "id")

az role assignment create --role "Managed Identity Operator" --assignee "$KUBENET_ID" --scope $NODES_RESOURCE_ID
az role assignment create --role "Virtual Machine Contributor" --assignee "$KUBENET_ID" --scope $NODES_RESOURCE_ID
```

Setup Key Vault

```bash
# Create Key Vault
VAULT_NAME="azure-k8s-vault"
az keyvault create --name $VAULT_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

# Create a Secret
SECRET_NAME="admin"
SECRET_VALUE="t0p-S3cr3t"
az keyvault secret set --name $SECRET_NAME --value $SECRET_VALUE --vault-name $VAULT_NAME

# Create a User Managed Identity
KV_IDENTITY_NAME="kv-access-identity"
az identity create --resource-group ${RESOURCE_GROUP} --name ${KV_IDENTITY_NAME}

# Assign the proper Role
KV_IDENTITY_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${KV_IDENTITY_NAME} --query id -otsv)"
KV_IDENTITY_OID="$(az identity show -g ${RESOURCE_GROUP} -n ${KV_IDENTITY_NAME} --query principalId -otsv)"
KUBENET_ID="$(az aks show -g ${RESOURCE_GROUP} -n ${AKS_NAME} --query identityProfile.kubeletidentity.clientId -otsv)"
az role assignment create --role "Managed Identity Operator" --assignee "$KUBENET_ID" --scope $KV_IDENTITY_ID

# Add Access Policy for Managed Identity
az keyvault set-policy --name $VAULT_NAME --resource-group $RESOURCE_GROUP --object-id $KV_IDENTITY_OID --key-permissions encrypt decrypt --secret-permissions get
```

Setup a Pod Identity and Deploy Sample

```bash
# Create a Pod Identity (Creates AzureIdentity and AzureIdentityBinding)
NAMESPACE="default"
az aks pod-identity add --resource-group $RESOURCE_GROUP --cluster-name $AKS_NAME --namespace $NAMESPACE  --name $KV_IDENTITY_NAME --identity-resource-id $KV_IDENTITY_ID

# Validate Identities
kubectl get AzureIdentity -n $NAMESPACE
kubectl get AzureIdentityBinding -n $NAMESPACE
```

Deploy Sample Application

```bash
# Deploy Secret Provider Class
cat <<EOF | kubectl apply --namespace default -f -
---
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    usePodIdentity: "true"
    keyvaultName: "$VAULT_NAME"
    tenantId: "$TENANT_ID"
    objects:  |
      array:
        - |
          objectName: admin
          objectType: secret
  secretObjects:
  - secretName: key-vault-secrets
    type: Opaque
    data:
    - objectName: admin
      key: admin-password
EOF

# Deploy Test Pod
cat <<EOF | kubectl apply --namespace default -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: vault-test
  namespace: default
  labels:
    aadpodidbinding: $KV_IDENTITY_NAME
spec:
  volumes:
    - name: azure-keyvault
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: azure-keyvault
  containers:
    - image: gcr.io/kuar-demo/kuard-amd64:1
      name: kuard
      ports:
        - containerPort: 8080
          name: http
          protocol: TCP
      volumeMounts:
        - name: azure-keyvault
          mountPath: "/mnt/azure-keyvault"
          readOnly: true
      env:
        - name: ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: key-vault-secrets
              key: admin-password
EOF

# Validate
kubectl exec vault-test -- ls /mnt/azure-keyvault/
kubectl exec vault-test -- cat /mnt/azure-keyvault/admin
kubectl exec vault-test -- env |grep ADMIN_PASSWORD
```

