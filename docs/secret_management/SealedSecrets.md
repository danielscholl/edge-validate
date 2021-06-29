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

# Create the Flux Source
flux create source helm sealed-secrets \
  --interval=5m \
  --url=https://bitnami-labs.github.io/sealed-secrets \
  --export > ./clusters/$AKS_NAME/sealed-secrets-source.yaml

# Create the Flux Helm Release (0.0.19 works for Secret Object Mapping)
flux create helmrelease sealed-secrets \
  --interval=5m \
  --release-name=sealed-secrets \
  --target-namespace=kube-system \
  --interval=10m \
  --source=HelmRepository/sealed-secrets \
  --chart=sealed-secrets \
  --chart-version=">=1.16.0-0" \
  --crds=CreateReplace \
  --export > ./clusters/$AKS_NAME/sealed-secrets-helm.yaml


# Update the Git Repo
git add ./clusters/$AKS_NAME/sealed-secrets-*.yaml && git commit -m "Installing Sealed Secrets" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl -n kube-system get pods

# Create a Secret
cat <<EOF | kubeseal \
    --controller-namespace kube-system \
    --controller-name sealed-secrets \
    --format yaml | kubectl apply --namespace default -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: sealed-secret
  namespace: default
type: Opaque
stringData:
  username: admin
  password: t0p-S3cr3t
EOF

# Validate & Delete Secret
kubectl describe secret sealed-secret && kubectl delete secret sealed-secret
```


**Install Sealed Secrets on the ARC Enabled Kubernetes Instance**
```bash
ARC_AKS_NAME="kind-k8s"
kubectl config use-context "kind-$ARC_AKS_NAME"

flux create source helm sealed-secrets \
  --interval=5m \
  --url=https://bitnami-labs.github.io/sealed-secrets \
  --export > ./clusters/$ARC_AKS_NAME/sealed-secrets-source.yaml

flux create helmrelease sealed-secrets \
  --interval=5m \
  --release-name=sealed-secrets \
  --target-namespace=kube-system \
  --interval=10m \
  --source=HelmRepository/sealed-secrets \
  --chart=sealed-secrets \
  --chart-version=">=1.16.0-0" \
  --crds=CreateReplace \
  --export > ./clusters/$ARC_AKS_NAME/sealed-secrets-helm.yaml

# Update the Git Repo
git add ./clusters/$ARC_AKS_NAME/sealed-secrets-* && git commit -m "Installing Sealed Secrets" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrepository -A
kubectl get helmrelease -A
kubectl -n kube-system get pods |grep sealed-secrets

# Retrieve the Public Key
kubeseal --fetch-cert \
  --controller-namespace kube-system \
  --controller-name sealed-secrets \
  >./clusters/$ARC_AKS_NAME/pub-cert.pem

# Update the Git Repo
git add ./clusters/$ARC_AKS_NAME/pub-cert.pem && git commit -m "Adding Public Key" && git push

# Create a Secret using the key
cat <<EOF | kubeseal \
    --cert=./clusters/$ARC_AKS_NAME/pub-cert.pem \
    --format yaml | kubectl apply --namespace default -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: sealed-secret
  namespace: default
type: Opaque
stringData:
  username: admin
  password: t0p-S3cr3t
EOF

# Validate Secret
kubectl describe secret sealed-secret
```
