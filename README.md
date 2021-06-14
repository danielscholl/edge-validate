# edge-validate

### Deploy Hello ARC Ingress

```powershell
$RESOURCE_GROUP = "arc-enabled-k8s"
$AKS_NAME = "arc-enabled-k8s"

# Deploy Ingress
az k8s-configuration create `
  --name sample-app `
  --cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP `
  --operator-instance-name sample-app --operator-namespace sample-app `
  --enable-helm-operator `
  --helm-operator-params='--set helm.versions=v3' `
  --repository-url "git@github.com:danielscholl/edge-validate.git" `
  --scope namespace --cluster-type connectedClusters `
  --operator-params="--git-path=release/sample-app --git-poll-interval 3s --git-branch=main --git-user=flux --git-email=flux@edge.microsoft.com" `
  --ssh-private-key-file "C:\Users\degno\.ssh\id_rsa"

# Deploy Sample App
az k8s-configuration create `
  --name sample-app-ingress `
  --cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP `
  --operator-instance-name sample-app-ingress --operator-namespace sample-app-ingress `
  --enable-helm-operator `
  --helm-operator-params="--set helm.versions=v3" `
  --repository-url "git@github.com:danielscholl/edge-validate.git" `
  --scope cluster --cluster-type connectedClusters `
  --operator-params="--git-path=release/sample-app-ingress --git-poll-interval 3s --git-branch=main --git-user=flux --git-email=flux@edge.microsoft.com" `
  --ssh-private-key-file "C:\Users\degno\.ssh\id_rsa"

# Validate
kubectl get svc -n sample-app-ingress -w
kubectl get pods -n sample-app -w
```

### Cleanup

```powershell
$RESOURCE_GROUP = "arc-enabled-k8s"
$AKS_NAME = "arc-enabled-k8s"

# Deleting GitOps Configurations from Azure Arc Kubernetes cluster
az k8s-configuration delete --name sample-app --cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP --cluster-type connectedClusters -y
az k8s-configuration delete --name sample-app-ingress --cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP --cluster-type connectedClusters -y

# Cleaning Kubernetes cluster
kubectl delete ns sample-app-ingress
kubectl delete ns sample-app

```