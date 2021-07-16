# Install Instructions

```bash
# Export Github Information as necessary
GITHUB_TOKEN="<your-github-token>"
GITHUB_REPO="<your-github-project>"
GITHUB_USER="<your-github-organization>"

# Setup a Cluster similar to AKS
CLUSTER="dev"
kind create cluster --config=kind/single-node.yaml --name=$CLUSTER

# Bootstrap Flux Components
flux bootstrap github --owner=$GITHUB_USER --repository=$GITHUB_REPO --branch=main --path=./clusters/$CLUSTER

# Clone the Repo
git clone git@github.com:$GITHUB_USER/$GITHUB_REPO.git flux-infra


# Create a Flux Git Source
flux create source git edge-validate \
  --url https://github.com/danielscholl/edge-validate \
  --interval 1m \
  --branch main \
  --export > flux-infra/clusters/$CLUSTER/edge-validate-source.yaml

# Create the Flux Kustomization for infra deployment
flux create kustomization edge-infra \
  --source=edge-validate \
  --path=./deploy/manifests \
  --prune=true \
  --interval=5m \
  --export > flux-infra/clusters/$CLUSTER/edge-validate-kustomization.yaml

# Create the Flux Release
flux create helmrelease akv2k8s \
  --interval=5m \
  --release-name=akv2k8s \
  --target-namespace=kube-system \
  --interval=5m \
  --source=HelmRepository/spv-charts \
  --chart=akv2k8s \
  --chart-version=">=2.0.0-0" \
  --crds=CreateReplace \
  --values-from=secret/akv2k8s-values.yaml \
  --export > $REPO_SOURCE/clusters/$ARC_AKS_NAME/akv2k8s-helm.yaml

```
