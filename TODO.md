# Validate AAD Pod Identity on AKS




1. AAD Pod Identity
    - https://github.com/Azure/aad-pod-identity


```powershell
$RESOURCE_GROUP = "arc-enabled-k8s"
$AKS_NAME = "arc-enabled-k8s"

# Deploy Identity
az k8s-configuration create `
  --name identity `
  --cluster-name $AKS_NAME --resource-group $RESOURCE_GROUP `
  --operator-instance-name identity --operator-namespace aad-pod-identity `
  --enable-helm-operator `
  --helm-operator-params="--set helm.versions=v3" `
  --repository-url "git@github.com:danielscholl/edge-validate.git" `
  --scope cluster --cluster-type connectedClusters `
  --operator-params="--git-path=release/identity --git-poll-interval 3s --git-branch=main --git-user=flux --git-email=flux@edge.microsoft.com" `
  --ssh-private-key-file "C:\Users\degno\.ssh\id_rsa"
```

2. Key Vault Integration 

    - https://akv2k8s.io/security/authentication/


