# Setup an AKS CLuster

```bash
RESOURCE_GROUP="azure-k8s"
AKS_NAME="azure-k8s"
LOCATION="eastus"

# Create Resource Group
az group create -n $RESOURCE_GROUP -l $LOCATION

# Create Cluster
az aks create -g $RESOURCE_GROUP -n $AKS_NAME --enable-managed-identity

# Get Credentials
az aks get-credentials -g $RESOURCE_GROUP -n $AKS_NAME
```