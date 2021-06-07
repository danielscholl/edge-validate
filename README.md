# edge-validate

### Deploy Hello ARC Ingress

```powershell
$RESOURCE_GROUP = "arc-enabled-k8s"
$AKS_NAME = "arc-enabled-k8s"


# Create Cluster-level GitOps-Config for deploying nginx-ingress
az k8s-configuration create `
--name nginx-ingress `
--cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP `
--operator-instance-name cluster-mgmt --operator-namespace cluster-mgmt `
--enable-helm-operator `
--helm-operator-params="--set helm.versions=v3" `
--repository-url "git@github.com:danielscholl/edge-validate.git" `
--scope cluster --cluster-type connectedClusters `
--operator-params="--git-poll-interval 3s --git-readonly --git-path=releases/nginx"

# Create Namespace-level GitOps-Config for deploying the "Hello Arc" application
az k8s-configuration create `
--name hello-arc `
--cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP `
--operator-instance-name hello-arc --operator-namespace prod `
--enable-helm-operator `
--helm-operator-params='--set helm.versions=v3' `
--repository-url "git@github.com:danielscholl/edge-validate.git" `
--scope namespace --cluster-type connectedClusters `
--operator-params="--git-poll-interval 3s --git-readonly --git-path=releases/prod"

```

### Cleanup

```powershell
$RESOURCE_GROUP = "arc-enabled-k8s"
$AKS_NAME = "arc-enabled-k8s"

# Deleting GitOps Configurations from Azure Arc Kubernetes cluster
az k8s-configuration delete --name hello-arc --cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP --cluster-type connectedClusters -y
az k8s-configuration delete --name nginx-ingress --cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP --cluster-type connectedClusters -y

# Cleaning Kubernetes cluster
kubectl delete ns prod
kubectl delete ns cluster-mgmt

kubectl delete clusterrole cluster-mgmt-helm-cluster-mgmt-helm-operator
kubectl delete clusterrole hello-arc-helm-prod-helm-operator-crd
kubectl delete clusterrole nginx-ingress

kubectl delete clusterrolebinding cluster-mgmt-helm-cluster-mgmt-helm-operator
kubectl delete clusterrolebinding hello-arc-helm-prod-helm-operator
kubectl delete clusterrolebinding nginx-ingress

kubectl delete secret sh.helm.release.v1.azure-arc.v1 -n default
```