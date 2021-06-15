# Instructions for Testing Managed Pod Identity

**Technical Links**

[Technical Blog](https://blog.baeke.info/2020/12/09/azure-ad-pod-managed-identities-in-aks-revisited/)
[Azure Documentation](https://docs.microsoft.com/en-us/azure/aks/use-azure-ad-pod-identity)

```bash
RESOURCE_GROUP="azure-k8s"
APP_IDENTITY="test-identity"

# Create a User Managed Identity
az identity create --resource-group ${RESOURCE_GROUP} --name ${APP_IDENTITY}
APP_IDENTITY_CLIENT_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${APP_IDENTITY} --query clientId -otsv)"
APP_IDENTITY_RESOURCE_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${APP_IDENTITY} --query id -otsv)"

# Assign Roles:  "Virtual Machine Contributor" and "Managed Identity Operator"
NODE_GROUP=$(az aks show -g ${RESOURCE_GROUP} -n $AKS_NAME --query nodeResourceGroup -o tsv)
NODES_RESOURCE_ID=$(az group show -n $NODE_GROUP -o tsv --query "id")
az role assignment create --role "Managed Identity Operator" --assignee "$APP_IDENTITY_CLIENT_ID" --scope $NODES_RESOURCE_ID

# Create Application Pod Identity
POD_IDENTITY="test-pod-identity"
NAMESPACE="demoapp"
az aks pod-identity add --name ${POD_IDENTITY} --resource-group $RESOURCE_GROUP --cluster-name $AKS_NAME --namespace ${NAMESPACE} --identity-resource-id ${APP_IDENTITY_RESOURCE_ID}

# Validate Pod Identity
az aks pod-identity list --cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP -otable

# Deploy Test Pod
cat <<EOF | kubectl apply --namespace demoapp -f -
apiVersion: v1
kind: Pod
metadata:
  name: identity-test
  labels:
    aadpodidbinding: test-pod-identity
spec:
  containers:
  - name: identity-test
    image: mcr.microsoft.com/oss/azure/aad-pod-identity/demo:v1.6.3
    args:
      - --subscriptionid=$(az account show --query id -otsv)
      - --clientid=${APP_IDENTITY_CLIENT_ID}
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

# Validate the Pod
kubectl logs identity-test --namespace demoapp
```
