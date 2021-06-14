# edge-validate

The purpose of this project is to attempt to validate certain technologies and patterns using Azure Arc enabled AKS. Github Code Spaces is used in an effort to eliminate the need for tooling environments.

## Prepare a Subscription

A Subscription has to be enabled for ARC Enabled Kubernetes along with the azure cli extensions loaded.

```bash
# Azure CLI Login
az login
az account set --subscription <your_subscription>

# Enable Preview Features
az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService
az feature show --name EnablePodIdentityPreview --namespace Microsoft.ContainerService

# Register Providers (one time action)
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ExtendedLocation
az provider register --namespace Microsoft.ContainerService

# Show Providers  (one time action)
az provider show -n Microsoft.Kubernetes -o table
az provider show -n Microsoft.KubernetesConfiguration -o table
az provider show -n Microsoft.ExtendedLocation -o table

# Add CLI Extensions
az extension add --name aks-preview
az extension add --name connectedk8s
az extension add --name k8s-configuration
az extension add --name k8s-extension
az extension add --name customlocation


```

## Setup an Azure Kubernetes Instance for reference validation

An AKS instance is setup to be used as a reference point comparision of what can be done on AKS vs and ARC enabled AKS. 
[Managed Identities](https://docs.microsoft.com/en-us/azure/aks/use-managed-identity) will be used in this AKS instance.


```bash
RESOURCE_GROUP="azure-k8s"
LOCATION="eastus"

# Create a Resource Group
az group create -n $RESOURCE_GROUP -l $LOCATION

# Create a Control Plane Identity
IDENTITY_NAME="aks-controlplane-identity"
az identity create -n $IDENTITY_NAME -g $RESOURCE_GROUP -l $LOCATION
IDENTITY_ID=$(az identity show -n $IDENTITY_NAME -g $RESOURCE_GROUP -o tsv --query "id")

# Create a Kubelet Identity
KUBELET_IDENTITY_NAME="aks-kubelet-identity"
az identity create -n $KUBELET_IDENTITY_NAME -g $RESOURCE_GROUP -l $LOCATION
KUBELET_IDENTITY_ID=$(az identity show -n $KUBELET_IDENTITY_NAME -g $RESOURCE_GROUP -o tsv --query "id")
KUBELET_IDENTITY_OID=$(az identity show -n $KUBELET_IDENTITY_NAME -g $RESOURCE_GROUP -o tsv --query "principalId")

# Create Cluster
AKS_NAME="azure-k8s"
az aks create -g $RESOURCE_GROUP -n $AKS_NAME --enable-managed-identity --assign-identity $IDENTITY_ID --assign-kubelet-identity $KUBELET_IDENTITY_ID --generate-ssh-keys

# Get Credentials
az aks get-credentials -g $RESOURCE_GROUP -n $AKS_NAME

# Validate Cluster
kubectl cluster-info --context $AKS_NAME

# Allow Kubelet "Virtual Machine Contributor" role
RESOURCE_GROUP_ID=$(az group show -n $RESOURCE_GROUP -o tsv --query id)
AKS_RESOURCE_GROUP_NAME=$(az aks show -g $RESOURCE_GROUP -n $AKS_NAME -o tsv --query nodeResourceGroup)
AKS_RESOURCE_GROUP_ID=$(az group show -n $AKS_RESOURCE_GROUP_NAME -o tsv --query id)
KUBELET_CLIENT_ID=$(az aks show -g $RESOURCE_GROUP -n $AKS_NAME -o tsv --query identityProfile.kubeletidentity.clientId)
az role assignment create --role "Virtual Machine Contributor" --assignee $KUBELET_CLIENT_ID --scope $AKS_RESOURCE_GROUP_ID
```

## Setup an ARC Enabled Kubernetes Instance for validation

Using Github Code Spaces create a Kubernetes Environment.

```bash
# Using kind create a Kubernetes Cluster
kind create cluster

# Arc enable the Kubernetes Cluster
ARC_AKS_NAME="kind-k8s"
az connectedk8s connect -n $ARC_AKS_NAME -g $RESOURCE_GROUP

# Validate ARC agents
kubectl cluster-info --context kind-kind
kubectl get pods -n azure-arc
```

## Validation - Gitops

**Technical Links**

**Options**

1. Flux CD

    [Process Documentation](./docs/gitops-management/1.FluxSetup.md)

        [X] AKS Process
        [X] ARC Enabled Process

        Questions Raised
        ----------------
        1. This leverages kustomizations controllers. Can the same pattern be accomplished with ARC GitOps?


![diagram](./docs/images/flux_diagram.png)

2. Azure ARC Gitops

    [Process Documentation]()

        [ ] AKS Process
        [X] ARC Enabled Process

        Questions Raised
        ----------------
        1. This is a feature only available to ARC Enabled Process. Is it an official RoadMap Item?

![diagram](./docs/images/arc_gitops_diagram.png)




## Validation - Identity Management

**Technical Links**

- [AAD Pod Identity](https://docs.microsoft.com/en-us/azure/aks/use-azure-ad-pod-identity)


**Options**

1. User Managed Identity with AAD Pod Identity

Azure AKS leverages AAD Pod Identity to allow a managed identity to access Azure Resources in a secure manner.  This feature is being built into the AKS experience as a first class citizen instead of a configured option.

![diagram](./docs/images/aad_pod_identity.png)

2. System Assigned Identity

    [Process Documentation]()

        [X] AKS Process
        [ ] ARC Enabled Process

        Questions Raised
        ----------------
        1. ARC Clusters can only leverage a System Assigned Identity.  Is the meta API available?

TODO:// Document and validate how System Assigned Identities can be used in ARC enabled Kubernetes

![diagram](./docs/images/identity_diagram.png)


## Validation - Secret Management

This validation requires an Azure Key Vault to be provisioned.

### Setup Azure KeyVault

```bash
VAULT_NAME="azure-k8s-vault"
RESOURCE_GROUP="azure-k8s"
LOCATION="eastus"

# Create Key Vault
az keyvault create --name $VAULT_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

# Create a Cryptographic Key
az keyvault key create --name sops-key --vault-name $VAULT_NAME --protection software --ops encrypt decrypt

# Create a User Managed Identity
KV_IDENTITY_NAME="kv-access-identity"
az identity create -n $KV_IDENTITY_NAME -g $RESOURCE_GROUP -l $LOCATION
KV_IDENTITY_OID=$(az identity show -n $KV_IDENTITY_NAME -g $RESOURCE_GROUP -o tsv --query "principalId")
KV_IDENTITY_ID=$(az identity show -n $KV_IDENTITY_NAME -g $RESOURCE_GROUP -o tsv --query "id")

# Add Access Policy for Managed Identity
az keyvault set-policy --name $VAULT_NAME --resource-group $RESOURCE_GROUP --object-id $KV_IDENTITY_OID --key-permissions encrypt decrypt
```

**Technical Links**
- [Tech Blog](https://techcommunity.microsoft.com/t5/azure-global/gitops-and-secret-management-with-aks-flux-cd-sops-and-azure-key/ba-p/2280068)
- [Managing Secrets Blog](https://dzone.com/articles/managing-kubernetes-secrets)
- [Azure Arc Blog](https://www.cloudwithchris.com/blog/azure-arc-for-apps-part-1/)

**Options**

1. Bitnami's [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)

    Sealed Secrets require an additional controller and a new SealedSecret CRD that is safe to store in a Git Repository.  After flux applies the SealedSecret object, the controller decrypts the sealed secret and applies the plain secrets.

    [Process Documentation]()

        [ ] AKS Process
        [ ] ARC Enabled Process

        Questions Raised
        ----------------

![diagram](./docs/images/sealed_secret_diagram.png)



2. Mozilla's [SOPS](https://github.com/mozilla/sops)

    Unlike Sealed Secrets, SOPS does not require any additional controller because Flux's kustomize-controller can perform the decryption of the secrets. SOPS has integration with Azure Key Vault to store the cryptographic used to encrypt and decrypt the secrets. Access to Key Vault is performed with an Azure Identity.

    [AKS Process Documentation](./docs/1.AksSetup.md)

        [X] AKS Process
        [ ] ARC Enabled Process

        Questions Raised
        ----------------
        1. Can a system assigned identity be used on Arc Enabled Kubernetes to access Key Vault?



![diagram](./docs/images/sops_diagram.png)




3. Azure Key Vault Provider for Secrets Store [CSI Driver](https://github.com/Azure/secrets-store-csi-driver-provider-azure)

This approach allows us to define our secrets in Key Vault and automatically make them available as Kubernetes secrets.
This option might be seen as breaking the GitOps workflow where the Git repository is the single source of truth for application desired state.

**!** This method is the method used for OSDU on Azure.

[ ] Validate this method.



4. Azure Key Vault to Kubernetes [(akv2k8s)](https://akv2k8s.io/)

This makes Azure Key Vault secrets, certificates and keys available in Kubernetes in a simple secure way leveraging the 12 Factor App principals and includes a controller pattern as well as an injector pattern.


[ ] Validate this method.