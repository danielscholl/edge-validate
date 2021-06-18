
```bash
RESOURCE_GROUP="azure-k8s"
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME

SUBSCRIPTION_ID="$(az account show --query id -otsv)"

NODE_RESOURCE_GROUP="$(az aks show -g ${RESOURCE_GROUP} -n ${AKS_NAME} --query nodeResourceGroup -otsv)"


CLUSTER_IDENTITY_ID="$(az aks show -g ${RESOURCE_GROUP} -n ${AKS_NAME} --query identityProfile.kubeletidentity.clientId -otsv)"


az role assignment create --role "Managed Identity Operator" --assignee "${CLUSTER_IDENTITY_ID}" --scope "/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${NODE_RESOURCE_GROUP}"

echo "Assigning 'Virtual Machine Contributor' role to ${ID}"
az role assignment create --role "Virtual Machine Contributor" --assignee "${CLUSTER_IDENTITY_ID}" --scope "/subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${NODE_RESOURCE_GROUP}"


# Deploy components
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment.yaml

# For AKS clusters, deploy the MIC and AKS add-on exception by running -
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/mic-exception.yaml

helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
helm install aad-pod-identity aad-pod-identity/aad-pod-identity
```
