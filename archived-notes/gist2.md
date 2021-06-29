# Validation: KV CSI Secret Driver with Service Principal

This validation  will use Service Principal and Key Vault CSI Secret Driver features to test secret management with Key Vault Secrets.


Create Azure Resources

```bash
# Azure CLI Login
az login
az account set --subscription <your_subscription>

RAND="$(echo $RANDOM | tr '[0-9]' '[a-z]')"


# Create a Service Principal
CLIENT_NAME="principal-$RAND"
CLIENT_SECRET=$(az ad sp create-for-rbac -n $CLIENT_NAME --skip-assignment --query password -o tsv)
CLIENT_ID=$(az ad sp list --display-name $CLIENT_NAME --query [].appId -o tsv)
TENANT_ID=$(az ad sp list --display-name $CLIENT_NAME --query [].appOwnerTenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -otsv)

# Assign a Role for Demo Pod Test Case
RESOURCE_GROUP_ID=$(az group show -n $RESOURCE_GROUP --query id -otsv)
az role assignment create --role "Managed Identity Operator" --assignee $CLIENT_ID --scope $RESOURCE_GROUP_ID
az role assignment create --role "Virtual Machine Contributor" --assignee $CLIENT_ID --scope $RESOURCE_GROUP_ID
```


Create test **Kubernetes Cluster**

```bash
# Using kind create a Kubernetes Cluster
kind create cluster

# Deploy CSI Driver
helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
helm install aad-pod-identity aad-pod-identity/aad-pod-identity --set operationMode=managed

# Validate
kubectl get pods
```

Deploy Sample Application

```bash
# Create a Secret
kubectl create secret generic secrets-store-creds \
  --from-literal clientsecret=$CLIENT_SECRET

# Validate the Secret Exists
kubectl describe Secret secrets-store-creds


# Deploy Azure Identity
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: demo-aad1-sp
type: Opaque
data:
  clientSecret: $(echo -n $CLIENT_SECRET | base64)
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: demo-aad1
spec:
  type: 1
  tenantID: $TENANT_ID
  clientID: $CLIENT_ID
  clientPassword: {"name":"demo-aad1-sp","namespace":"default"}
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: demo-azure-id-binding
spec:
  azureIdentity: "demo-aad1"
  selector: "demo"
---
apiVersion: v1
kind: Pod
metadata:
  name: demo
  labels:
    aadpodidbinding: demo
spec:
  containers:
  - name: identity-test
    image: mcr.microsoft.com/oss/azure/aad-pod-identity/demo:v1.6.3
    args:
      - --subscriptionid=${SUBSCRIPTION_ID}
      - --clientid=${CLIENT_ID}
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

# Validate
kubectl logs demo

```
