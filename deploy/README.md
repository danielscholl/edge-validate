# Install Instructions using Scripts

## Create a Cluster

> Ensure your Github tokens are setup correctly.

```bash
#########################
### CONFIGURE CLUSTER ###
#########################
GITHUB_TOKEN="<your-github-token>"
GITHUB_REPO="<your-github-project>"
GITHUB_USER="<your-github-organization>"

# Move to Script Directory
cd scripts

# Setup the Cluster
CLUSTER="dev"
./create_cluster.sh

# Configure the Cluster
./configure_cluster.sh      # --> Approve the Pull Request

# Validate the load
kubectl get helmreleases -A -w

# Deploy Azure Resources for the Sample App (keyvault and identity)
./provision_azure.sh

# ARC Enable the Cluster (Optional)
RESOURCE_GROUP="validate-sample"
ARC_AKS_NAME="kind-dev"
az connectedk8s connect -n $ARC_AKS_NAME -g $RESOURCE_GROUP

# Deploy Azure Monitor (Optional)
az k8s-extension create --name azuremonitor-containers  --extension-type Microsoft.AzureMonitor.Containers --scope cluster --cluster-name $ARC_AKS_NAME --resource-group $RESOURCE_GROUP --cluster-type connectedClusters

# Deploy a sample app
./configure_application.sh   # --> Approve the Pull Request

# Validate the load
kubectl get helmreleases -A -w
```
