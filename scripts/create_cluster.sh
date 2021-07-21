#!/usr/bin/env bash
#
#  Purpose: Create the local Kind Cluster.
#  Usage:
#    create_cluster.sh

###############################
## ARGUMENT INPUT            ##
###############################
usage() { echo "Usage: remove.sh " 1>&2; exit 1; }

if [ ! -z $1 ]; then CLUSTER=$1; fi
if [ -z $CLUSTER ]; then
  CLUSTER="dev"
fi

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
  FLUX_DIR="../flux-infra"
else
  FLUX_DIR="flux-infra"
fi

BASE_DIR=$(pwd)

# Setup Kind Cluster
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

# Install Calico Networking and NGINX Ingress Controller
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Scale down CoreDNS to save resources
kubectl scale deployment --replicas 1 coredns --namespace kube-system

sleep 35

# Validate the Node is Ready
kubectl get nodes

# Bootstrap Flux Components
flux bootstrap github --owner=$GITHUB_USER --repository=$GITHUB_REPO --branch=main --path=./clusters/$CLUSTER

# Clone the Repo
git clone git@github.com:$GITHUB_USER/$GITHUB_REPO.git $FLUX_DIR
