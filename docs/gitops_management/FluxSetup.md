# Instructions for Setting up Flux

Install Flux in the clusters.
> This process will perform a checkin on the git repository /clusters/`$AKS_NAME`/flux-system

**Technical Links**

[Bootstrap with Github](https://fluxcd.io/docs/installation/#github-and-github-enterprise)


**Install Flux on the Azure Kubernetes Instance**
```bash
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME

# Validate Flux requirements
flux check --pre

# Export Github Information as necessary
GITHUB_TOKEN="<your-github-token>"
GITHUB_REPO="<your-github-project>"
GITHUB_USER="<your-github-organization>"

# Bootstrap Flux Components
flux bootstrap github --owner=$GITHUB_USER --repository=$GITHUB_REPO --branch=main --path=./clusters/$AKS_NAME

# Validate
flux check
kubectl get Kustomization -A

# Pull Latest
git pull
```

**Install Flux on the ARC Enabled Kubernetes Instance**
```bash
ARC_AKS_NAME="kind-k8s"
kubectl config use-context "kind-$ARC_AKS_NAME"

# Validate Flux requirements
flux check --pre

# Export Github Information as necessary
GITHUB_TOKEN="<your-github-token>"
GITHUB_REPO="<your-github-project>"
GITHUB_USER="<your-github-organization>"


# Bootstrap Flux Components
flux bootstrap github --owner=$GITHUB_USER --repository=$GITHUB_REPO --branch=main --path=./clusters/$ARC_AKS_NAME

# Validate
flux check
kubectl get Kustomization -A

# Pull Latest
git pull
```