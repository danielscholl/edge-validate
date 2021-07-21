#!/usr/bin/env bash
#
#  Purpose: Remove the local Kind Cluster.
#  Usage:
#    remove.sh

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

kind delete cluster --name $CLUSTER

rm -rf $FLUX_DIR/clusters
rm -rf $FLUX_DIR/apps
cd $FLUX_DIR
git pull
git add -f clusters
git add -f apps
git commit -am "Removing Cluster"
git push
cd $BASE_DIR
rm -rf $FLUX_DIR
