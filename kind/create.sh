#!/bin/bash

set -e

kind create cluster --config=kind/single-node.yaml --name $1

# Calico
curl https://docs.projectcalico.org/manifests/calico.yaml | kubectl apply -f -

# CoreDNS
kubectl scale deployment --replicas 1 coredns --namespace kube-system

# Metrics Server
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm upgrade metrics-server --install bitnami/metrics-server --namespace kube-system --set apiService.create=true --set extraArgs.kubelet-insecure-tls=true --set extraArgs.kubelet-preferred-address-types=InternalIP
