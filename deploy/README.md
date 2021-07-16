# Install Instructions

```bash
# Export Github Information as necessary
GITHUB_TOKEN="<your-github-token>"
GITHUB_REPO="<your-github-project>"
GITHUB_USER="<your-github-organization>"

# Setup a Cluster similar to AKS
CLUSTER="dev"
kind create cluster --config=kind/single-node.yaml --name=$CLUSTER

# Scale down CoreDNS
kubectl scale deployment --replicas 1 coredns --namespace kube-system

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

# Update the Git Repo
BASE_DIR=$(pwd)
cd flux-infra && \
  git add -f clusters/$CLUSTER/edge-validate-*.yaml && \
  git commit -am "Configuring Edge-Validate Deployments" && \
  git push && \
  cd $BASE_DIR

# Validate the Deployment
flux reconcile kustomization flux-system --with-source


```
