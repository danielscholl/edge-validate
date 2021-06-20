# Instructions for creating a Gitops Configuration

Install the config-agent in the cluster which deploys a flux operator to watch the git repository for each configuration.

> This process is multi-tenancy and can be cluster or namespace scoped.


**Technical Links**

[Bootstrap with Github](https://fluxcd.io/docs/installation/#github-and-github-enterprise)


**Install a sample app**

> Configure the github repository with the default SSH Key `cat ~/.ssh/id_rsa.pub` as a deploy key with write access.

```bash
RESOURCE_GROUP="azure-k8s"
ARC_AKS_NAME="kind-k8s"

kubectl config use-context "kind-$ARC_AKS_NAME"

# Deploy Sample App
az k8s-configuration create \
  --name sample-app \
  --cluster-name $ARC_AKS_NAME --resource-group $RESOURCE_GROUP \
  --operator-instance-name sample-app --operator-namespace sample-app \
  --enable-helm-operator \
  --helm-operator-params='--set helm.versions=v3' \
  --repository-url "git@github.com:danielscholl/edge-validate.git" \
  --scope namespace --cluster-type connectedClusters \
  --operator-params="--git-path=release/sample-app --git-poll-interval 3s --git-branch=main --git-user=flux --git-email=flux@edge.microsoft.com" \
  --ssh-private-key-file "/home/vscode/.ssh/id_rsa"

# Validate the Deployment
az k8s-configuration show --name sample-app --resource-group $RESOURCE_GROUP --cluster-name $ARC_AKS_NAME --cluster-type connectedClusters --query complianceStatus
kubectl get pods -n sample-app -w

# Deploy Ingress (LoadBalancer Ingress not supported by Kind Clusters)
az k8s-configuration create \
  --name sample-app-ingress \
  --cluster-name $ARC_AKS_NAME --resource-group $RESOURCE_GROUP \
  --operator-instance-name sample-app-ingress --operator-namespace sample-app-ingress \
  --enable-helm-operator \
  --helm-operator-params="--set helm.versions=v3" \
  --repository-url "git@github.com:danielscholl/edge-validate.git" \
  --scope cluster --cluster-type connectedClusters \
  --operator-params="--git-path=release/sample-app-ingress --git-poll-interval 3s --git-branch=main --git-user=flux --git-email=flux@edge.microsoft.com" \
  --ssh-private-key-file "/home/vscode/.ssh/id_rsa"

# Validate the Deployment
az k8s-configuration show --name sample-app-ingress --resource-group $RESOURCE_GROUP --cluster-name $ARC_AKS_NAME --cluster-type connectedClusters --query complianceStatus
kubectl get svc -n sample-app-ingress -w
```


**Cleanup** *(optional)*

```bash
# Deleting GitOps Configurations from Azure Arc Kubernetes cluster
az k8s-configuration delete --name sample-app --resource-group $RESOURCE_GROUP --cluster-name $ARC_AKS_NAME --cluster-type connectedClusters -y
az k8s-configuration delete --name sample-app-ingress --resource-group $RESOURCE_GROUP --cluster-name $ARC_AKS_NAME --cluster-type connectedClusters -y

# Cleaning Kubernetes cluster
kubectl delete ns sample-app-ingress
kubectl delete ns sample-app
```