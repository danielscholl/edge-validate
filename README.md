# edge-validate

### Deploy Hello ARC Ingress

```powershell
$RESOURCE_GROUP = "arc-enabled-k8s"
$AKS_NAME = "arc-enabled-k8s"

az k8s-configuration create `
  --name nginx-ingress `
  --cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP `
  --operator-instance-name cluster-mgmt --operator-namespace cluster-mgmt `
  --enable-helm-operator `
  --helm-operator-params="--set helm.versions=v3" `
  --repository-url "https://github.com/danielscholl/hello_arc.git" `
  --scope cluster --cluster-type connectedClusters `
  --operator-params="--git-path=releases/nginx --git-poll-interval 3s --git-branch=master"

az k8s-configuration create `
  --name hello-arc `
  --cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP `
  --operator-instance-name hello-arc --operator-namespace prod `
  --enable-helm-operator `
  --helm-operator-params='--set helm.versions=v3' `
  --repository-url "https://github.com/danielscholl/hello_arc.git" `
  --scope namespace --cluster-type connectedClusters `
  --operator-params="--git-path=releases/prod --git-poll-interval 3s --git-branch=master"


az k8s-configuration create `
--name nginx-ingress `
--cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP `
--operator-instance-name cluster-mgmt --operator-namespace cluster-mgmt `
--enable-helm-operator `
--helm-operator-params="--set helm.versions=v3" `
--repository-url "git@github.com:danielscholl/edge-validate.git" `
--scope cluster --cluster-type connectedClusters `
--operator-params="--git-path=releases/nginx --git-poll-interval 3s --git-branch=main --git-user=fluxv1 --git-email=fluxv1@example.com"

# Create Namespace-level GitOps-Config for deploying the "Hello Arc" application
az k8s-configuration create `
--name hello-arc `
--cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP `
--operator-instance-name hello-arc --operator-namespace prod `
--enable-helm-operator `
--helm-operator-params='--set helm.versions=v3' `
--repository-url "git@github.com:danielscholl/edge-validate.git" `
--scope namespace --cluster-type connectedClusters `
--operator-params="--git-path=releases/prod --git-poll-interval 3s --git-branch=main --git-user=fluxv1 --git-email=fluxv1@example.com"

kubectl get svc -n  cluster-mgmt -w
kubectl get pods -n prod -w

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
kubectl delete clusterrole nginx-ingress

kubectl delete clusterrolebinding cluster-mgmt-helm-cluster-mgmt-helm-operator
kubectl delete clusterrolebinding nginx-ingress

kubectl delete secret sh.helm.release.v1.azure-arc.v1 -n default
```