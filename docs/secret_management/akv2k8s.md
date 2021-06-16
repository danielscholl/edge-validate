

https://akv2k8s.io/installation/outside-azure-aks/

principalName="http://akv2k8s-principal"
AZURE_CLIENT_SECRET=$(az ad sp create-for-rbac -n $principalName --role contributor --query password -o tsv)
AZURE_CLIENT_ID=$(az ad sp show --id $principalName --query appId -o tsv)



helm upgrade --install akv2k8s spv-charts/akv2k8s \
  --namespace akv2k8s \
  --set global.keyVaultAuth=environment \
  --set global.env.AZURE_TENANT_ID=$(az account show --query tenantId -o tsv) \
  --set global.env.AZURE_CLIENT_ID=$AZURE_CLIENT_ID \
  --set global.env.AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET 