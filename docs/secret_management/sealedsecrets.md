# Instructions for Sealed Secrets

Install Bitnami Sealed Secrets in the clusters.
> This process will perform a checkin on the git repository /clusters/`$AKS_NAME`/flux-system

**Technical Links**


**Install Sealed Secrets on the Azure Kubernetes Instance**

```bash
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME

cat > ./clusters/$AKS_NAME/sealed-secrets.yaml <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: sealed-secrets
---
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: HelmRepository
metadata:
  name: sealed-secrets
  namespace: sealed-secrets
spec:
  interval: 10m0s
  url: https://bitnami-labs.github.io/sealed-secrets
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: sealed-secrets
  namespace: sealed-secrets
spec:
  chart:
    spec:
      chart: sealed-secrets
      sourceRef:
        kind: HelmRepository
        name: sealed-secrets
      version: '>=1.16.0-0'
  install:
    crds: Create
  interval: 10m0s
  releaseName: sealed-secrets
  targetNamespace: sealed-secrets
  upgrade:
    crds: CreateReplace
EOF

# Update the Git Repo
git add ./clusters/$AKS_NAME/sealed-secrets.yaml && git commit -m "Installing Sealed Secrets" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl -n sealed-secrets get pods

```