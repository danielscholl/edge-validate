# Instructions for Sealed Secrets

Install Bitnami Sealed Secrets in the clusters.
> This process will perform a checkin on the git repository /clusters/`$AKS_NAME`/flux-system

**Technical Links**

[Tutorial](https://www.arthurkoziel.com/encrypting-k8s-secrets-with-sealed-secrets/)
[Blog](https://blog.sighup.io/sealed-secrets-in-gitops/)



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
  namespace: flux-system
spec:
  interval: 10m0s
  url: https://bitnami-labs.github.io/sealed-secrets
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: sealed-secrets
  namespace: flux-system
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
  targetNamespace: kube-system
  upgrade:
    crds: CreateReplace
EOF

# Update the Git Repo
git add ./clusters/$AKS_NAME/sealed-secrets.yaml && git commit -m "Installing Sealed Secrets" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl -n kube-system get pods

# Create a temporary Secret
cat > ./secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: app-credentials
  namespace: default
type: Opaque
stringData:
  username: admin
  password: t0p-S3cr3t
EOF

# Seal a Secret
cat secret.yaml | kubeseal \
    --controller-namespace kube-system \
    --controller-name sealed-secrets \
    --format yaml \
    > ./clusters/$AKS_NAME/secret-enc.yaml && rm secret.yaml

    
# Deploy and Validate Secret
git add ./clusters/$AKS_NAME/secret-enc.yaml && git commit -m "Add Secret" && git push
kubectl describe secret -n default app-credentials

```


**Install Sealed Secrets on the ARC Enabled Kubernetes Instance**
```bash
ARC_AKS_NAME="kind-k8s"
kubectl config use-context "kind-$ARC_AKS_NAME"

cat > ./clusters/$ARC_AKS_NAME/sealed-secrets.yaml <<EOF
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
  namespace: flux-system
spec:
  interval: 10m0s
  url: https://bitnami-labs.github.io/sealed-secrets
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: sealed-secrets
  namespace: flux-system
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
  targetNamespace: kube-system
  upgrade:
    crds: CreateReplace
EOF

# Update the Git Repo
git add ./clusters/$ARC_AKS_NAME/sealed-secrets.yaml && git commit -m "Installing Sealed Secrets" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl -n kube-system get pods

# Create a temporary Secret
cat > ./secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: app-credentials
  namespace: default
type: Opaque
stringData:
  username: admin
  password: t0p-S3cr3t
EOF

# Seal a Secret
cat secret.yaml | kubeseal \
    --controller-namespace kube-system \
    --controller-name sealed-secrets \
    --format yaml \
    > secret-enc.yaml && rm secret.yaml

    
# Deploy and Validate Secret
kubectl apply -f secret-enc.yaml
kubectl describe secret -n default app-credentials
```