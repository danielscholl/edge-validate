#!/usr/bin/env bash
#
#  Purpose: Create Azure Resources.
#  Usage:
#    provision_azure.sh

###############################
## ARGUMENT INPUT            ##
###############################
usage() { echo "Usage: provision_azure.sh " 1>&2; exit 1; }

if [ ! -z $1 ]; then CLUSTER=$1; fi
if [ -z $CLUSTER ]; then
  CLUSTER="dev"
fi

if [ ! -z $2 ]; then RESOURCE_GROUP=$2; fi
if [ -z $RESOURCE_GROUP ]; then
  RESOURCE_GROUP="validate-sample"
fi

if [ ! -z $3 ]; then LOCATION=$3; fi
if [ -z $LOCATION ]; then
  LOCATION="eastus"
fi


RAND="$(echo $RANDOM | tr '[0-9]' '[a-z]')"
VAULT_NAME="kv-$RAND"
PRINCIPAL_NAME="principal-$RAND"
TENANT_ID=$(az account show --query tenantId -otsv)
SUBSCRIPTION_ID=$(az account show --query id -otsv)


SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  TARGET="$(readlink "$SOURCE")"
  if [[ $TARGET == /* ]]; then
    echo "SOURCE '$SOURCE' is an absolute symlink to '$TARGET'"
    SOURCE="$TARGET"
  else
    DIR="$( dirname "$SOURCE" )"
    echo "SOURCE '$SOURCE' is a relative symlink to '$TARGET' (relative to '$DIR')"
    SOURCE="$DIR/$TARGET" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  fi
done

RDIR="$( dirname "$SOURCE" )"
if [[ $RDIR == '.' ]]; then
  HOME_DIR="../"
else
  HOME_DIR="."
fi


# Create a Resource Group
az group create -n $RESOURCE_GROUP -l $LOCATION

# Create Key Vault
az keyvault create --name $VAULT_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

# Create a Secret
SECRET_NAME="admin"
SECRET_VALUE="t0p-S3cr3t"
az keyvault secret set --name $SECRET_NAME --value $SECRET_VALUE --vault-name $VAULT_NAME

# Create a Service Principal for validation
PRINCIPAL_SECRET=$(az ad sp create-for-rbac -n $PRINCIPAL_NAME --skip-assignment --query password -o tsv)
PRINCIPAL_ID=$(az ad sp list --display-name $PRINCIPAL_NAME --query [].appId -o tsv)
PRINCIPAL_OID=$(az ad sp list --display-name $PRINCIPAL_NAME --query [].objectId -o tsv)

# Provide Access to the Service Principal
az keyvault set-policy --name $VAULT_NAME --resource-group $RESOURCE_GROUP --object-id $PRINCIPAL_OID --key-permissions encrypt decrypt --secret-permissions get --certificate-permissions get

# Create Terraform envrc file
echo "============================================================================================================="
echo -n "Generating ENVRC File..."
echo
cat > $HOME_DIR/.envrc << EOF
export TENANT_ID=$TENANT_ID
export SUBSCRIPTION_ID=$SUBSCRIPTION_ID
export VAULT_NAME=$VAULT_NAME
export PRINCIPAL_ID=$PRINCIPAL_ID
export PRINCIPAL_SECRET=$PRINCIPAL_SECRET
EOF

