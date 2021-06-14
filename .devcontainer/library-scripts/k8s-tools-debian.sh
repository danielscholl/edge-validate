#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs:https://community.opengroup.org/osdu/platform/deployment-and-operations/infra-azure-provisioning
# Maintainer: Microsoft OSDU on Azure Teams
#
# Syntax: ./k8s-tools-debian.sh

KIND_VERSION=${1:-"v0.11.1"}
HELM_VERSION=${1:-"v3.2.2"}
SOPS_VERSION=${1:-"v3.7.1"}

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi


echo "================================================================================"
echo "Installing kind command."
wget -q https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-$(uname)-amd64 -O /usr/local/bin/kind
chmod 755 /usr/local/bin/kind
echo "The kind command line tool is installed... Done."


echo "================================================================================"
echo "Installing flux command."
curl -s https://fluxcd.io/install.sh | bash;
echo "The flux command line tool is installed... Done."


echo "================================================================================"
echo "Installing kubectl command."
latest=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
curl -LO https://storage.googleapis.com/kubernetes-release/release/$latest/bin/linux/amd64/kubectl && mv kubectl /usr/local/bin
chmod 755 /usr/local/bin/kubectl
echo "The kubectl command line tool is installed... Done."


echo "================================================================================="
echo "Installing helm command."
wget -q https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz -O helm-$HELM_VERSION-linux-amd64.tar.gz
tar -zxvf helm-$HELM_VERSION-linux-amd64.tar.gz -C /usr/local/bin --strip-components=1 linux-amd64/helm 
echo "The helm command line tool is installed... Done."

echo "================================================================================="
echo "Installing sops command."
wget -q https://github.com/mozilla/sops/releases/download/$SOPS_VERSION/sops-$SOPS_VERSION.linux -O /usr/local/bin/sops
chmod 755 /usr/local/bin/sops
echo "The sops command line tool is installed... Done."
