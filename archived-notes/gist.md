# Validation: KV CSI Secret Driver with Service Principal

This validation  will use Service Principal and Key Vault CSI Secret Driver features to test secret management with Key Vault Secrets.


Create Azure Resources

```bash

# Azure CLI Login
az login
az account set --subscription <your_subscription>

RAND="$(echo $RANDOM | tr '[0-9]' '[a-z]')"
RESOURCE_GROUP="kv-test-$RAND"
LOCATION="eastus"

# Create a Resource Group
az group create -n $RESOURCE_GROUP -l $LOCATION

# Create Key Vault
VAULT_NAME="vault-$RAND"
az keyvault create --name $VAULT_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

# Create a Secret
SECRET_NAME="secret1"
SECRET_VALUE="t0p-S3cr3t"
az keyvault secret set --name $SECRET_NAME --value $SECRET_VALUE --vault-name $VAULT_NAME

# Create a Service Principal
CLIENT_NAME="principal-$RAND"
CLIENT_SECRET=$(az ad sp create-for-rbac -n $CLIENT_NAME --skip-assignment --query password -o tsv)
CLIENT_ID=$(az ad sp list --display-name $CLIENT_NAME --query [].appId -o tsv)
CLIENT_OID=$(az ad sp list --display-name $CLIENT_NAME --query [].objectId -o tsv)
TENANT_ID=$(az ad sp list --display-name $CLIENT_NAME --query [].appOwnerTenantId -o tsv)

# Add Access Policy for Service Principal
az keyvault set-policy --name $VAULT_NAME --resource-group $RESOURCE_GROUP --object-id $CLIENT_OID --key-permissions encrypt decrypt --secret-permissions get --certificate-permissions get
```


Create test **Kubernetes Cluster**

```bash
# Using kind create a Kubernetes Cluster
kind create cluster

# Deploy CSI Driver
helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name

# Validate
kubectl get pods
```



Deploy Sample Application

```bash
# Create a Secret
kubectl create secret generic secrets-store-creds \
  --from-literal clientid=$CLIENT_ID \
  --from-literal clientsecret=$CLIENT_SECRET

# Validate the Secret Exists
kubectl describe Secret secrets-store-creds


# Deploy SecretProviderClass
cat <<EOF | kubectl apply -f -
---
# This is a SecretProviderClass example using a service principal to access Keyvault
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"         # [OPTIONAL] if not provided, will default to "false"
    keyvaultName: "$VAULT_NAME"     # the name of the KeyVault
    cloudName: ""                   # [OPTIONAL for Azure] if not provided, azure environment will default to AzurePublicCloud
    objects:  |
      array:
        - |
          objectName: secret1
          objectType: secret        # object types: secret, key or cert
          objectVersion: ""         # [OPTIONAL] object versions, default to latest if empty
    tenantId: "$TENANT_ID"
EOF

cat <<EOF | kubectl apply -f -
---
# This is a sample pod definition for using SecretProviderClass and service-principal to access Keyvault
kind: Pod
apiVersion: v1
metadata:
  name: busybox-secrets-store-inline
spec:
  containers:
  - name: busybox
    image: k8s.gcr.io/e2e-test-images/busybox:1.29
    command:
      - "/bin/sleep"
      - "10000"
    volumeMounts:
    - name: secrets-store-inline
      mountPath: "/mnt/secrets-store"
      readOnly: true
  volumes:
    - name: secrets-store-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "azure-keyvault"
        nodePublishSecretRef:                       # Only required when using service principal mode
          name: secrets-store-creds                 # Only required
EOF

# Validate
kubectl exec busybox-secrets-store-inline -- ls /mnt/secrets-store
kubectl exec busybox-secrets-store-inline -- cat /mnt/secrets-store/secret1

