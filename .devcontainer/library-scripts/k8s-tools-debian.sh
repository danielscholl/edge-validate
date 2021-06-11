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

HELM_VERSION=${1:-"v3.2.2"}

set -e

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
