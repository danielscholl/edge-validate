#!/usr/bin/env bash
#
#  Purpose: Deploy Edge Infrastructure Software.
#  Usage:
#    install_edge_infra.sh

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
RAND="$(echo $RANDOM | tr '[0-9]' '[a-z]')"

# Create the Branch
BASE_DIR=$(pwd)
cd $FLUX_DIR
git pull origin main
git checkout -b flux_$RAND
cd $BASE_DIR

# Create the Edge Validate Git Source
flux create source git edge-validate \
  --url https://github.com/danielscholl/edge-validate \
  --interval 1m \
  --branch main \
  --export > $FLUX_DIR/clusters/$CLUSTER/edge-infra-source.yaml

# Create the Edge Validate Kustomization
flux create kustomization edge-infra \
  --source=edge-validate \
  --path=./deploy/manifests \
  --prune=true \
  --interval=5m \
  --export > $FLUX_DIR/clusters/$CLUSTER/edge-infra-kustomization.yaml

# Update the Git Repo
BASE_DIR=$(pwd)
cd $FLUX_DIR
git add -f clusters/$CLUSTER/edge-infra-*.yaml
git commit -am "Configuring Edge-Infra Deployments"
git push origin flux_$RAND
gh pr create --title "Cluster Configuration Management" --body "This PR will deploy edge-infrastucture software to the $CLUSTER cluster."
git checkout main
git branch -D flux_$RAND
cd $BASE_DIR


