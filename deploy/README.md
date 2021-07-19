# Install Instructions

```bash
######################
### CREATE CLUSTER ###
######################
CLUSTER="dev"

# Setup a Cluster likeAKS with Calico as Network Plugin with IngressPort = 30000,300001
cat <<EOF | kind create cluster --name=$CLUSTER --config=-
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
networking:
  apiServerAddress: "127.0.0.1"
  apiServerPort: 6443
  podSubnet: "10.240.0.0/16"
  serviceSubnet: "10.0.0.0/16"
  disableDefaultCNI: true
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 30000
    hostPort: 80
    listenAddress: "127.0.0.1"
    protocol: TCP
  - containerPort: 30001
    hostPort: 443
    listenAddress: "127.0.0.1"
    protocol: TCP
  - containerPort: 30002
    hostPort: 15021
    listenAddress: "127.0.0.1"
    protocol: TCP
EOF

# Install Calico Networking
curl https://docs.projectcalico.org/manifests/calico.yaml | kubectl apply -f -

# Scale down CoreDNS to save resources
kubectl scale deployment --replicas 1 coredns --namespace kube-system

# Validate the Node is Ready
kubectl get nodes -w


#########################
### CONFIGURE CLUSTER ###
#########################
GITHUB_TOKEN="<your-github-token>"
GITHUB_REPO="<your-github-project>"
GITHUB_USER="<your-github-organization>"

# Bootstrap Flux Components
flux bootstrap github --owner=$GITHUB_USER --repository=$GITHUB_REPO --branch=main --path=./clusters/$CLUSTER

# Clone the Repo
git clone git@github.com:$GITHUB_USER/$GITHUB_REPO.git flux-infra

# Create the Edge Validate Git Source
flux create source git edge-validate \
  --url https://github.com/danielscholl/edge-validate \
  --interval 1m \
  --branch main \
  --export > flux-infra/clusters/$CLUSTER/edge-validate-source.yaml

# Create the Edge Validate Kustomization
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



**Cleanup** *(optional)*

```bash
# Remove the KinD Cluster
kind delete cluster --name $CLUSTER

# Remove the Cluster Configuration
rm -rf flux-infra/clusters/$CLUSTER

# Update the Git Repo
BASE_DIR=$(pwd)
cd flux-infra && \
  git add -f clusters/$CLUSTER && \
  git commit -am "Removing Cluster" && \
  git push && \
  cd $BASE_DIR
```
