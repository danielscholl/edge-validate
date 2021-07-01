# Instructions for Azure Key Vault to Kubernetes

Install the akv2k8s in the clusters.

**Technical Links**

[Documentation](https://akv2k8s.io/)

**Install CSI Driver on the Azure Kubernetes Instance**

```bash
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME

# Create the Flux Source
flux create source helm spv-charts \
--interval=5m \
--url=https://charts.spvapi.no \
--export > ./clusters/$AKS_NAME/akv2k8s-source.yaml

cat > values.yaml <<EOF
addAzurePodIdentityException: true
EOF

# Create the Flux Helm Release
flux create helmrelease akv2k8s \
  --interval=5m \
  --release-name=akv2k8s \
  --target-namespace=kube-system \
  --interval=5m \
  --source=HelmRepository/spv-charts \
  --chart=akv2k8s \
  --chart-version=">=2.0.0-0" \
  --crds=CreateReplace \
  --values=values.yaml \
  --export > ./clusters/$AKS_NAME/akv2k8s-helm.yaml && rm values.yaml

# Update the Git Repo
git add ./clusters/$AKS_NAME/akv2k8s-*.yaml && git commit -m "Installing avk2k8s" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl get pods -n kube-system |grep akv2k8s
```

Deploy a Sample

> Requires KV and Access Policy to KUBENET_OID

```bash
VAULT_NAME="azure-k8s-vault"

# Deploy Sample
cat << EOF | kubectl apply --namespace default -f -
---
apiVersion: spv.no/v2beta1
kind: AzureKeyVaultSecret
metadata:
  name: test-secret
  namespace: default
spec:
  vault:
    name: $VAULT_NAME
    object:
      name: admin
      type: secret
  output:
    secret:
      name: akv2k8s-test-secret
      dataKey: admin-password
---
apiVersion: v1
kind: Pod
metadata:
  name: env-test
spec:
  containers:
  - name: envar-demo-container
    image: gcr.io/google-samples/node-hello:1.0
    env:
    - name: MAP_SECRET
      valueFrom:
        secretKeyRef:
          name: akv2k8s-test-secret
          key: admin-password
EOF

# Validate
kubectl exec env-test -- printenv MAP_SECRET
```

**ARC Enabled Instance**

> Requires Sealed Secrets and KV_PRINCIPAL created

```bash
ARC_AKS_NAME="kind-k8s"
kubectl config use-context kind-$ARC_AKS_NAME

# Create Outside AKS values
VALUES_YAML=$(cat <<EOF | base64
global:
  keyVaultAuth: environment
  env:
    AZURE_TENANT_ID: $TENANT_ID
    AZURE_CLIENT_ID: $KV_PRINCIPAL_ID
    AZURE_CLIENT_SECRET: $KV_PRINCIPAL_SECRET
EOF
)

# Put Values in a Secret File
cat > secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: akv2k8s-values.yaml
  namespace: flux-system
type: Opaque
data:
  values.yaml: $VALUES_YAML
EOF

# Seal the Secret File
cat secret.yaml | kubeseal \
    --cert=./clusters/$ARC_AKS_NAME/pub-cert.pem \
    --format yaml > ./clusters/$ARC_AKS_NAME/akv2k8s-secret-values.yaml && secret.yaml

# Create the Flux Source
flux create source helm spv-charts \
--interval=5m \
--url=https://charts.spvapi.no \
--export > ./clusters/$ARC_AKS_NAME/akv2k8s-source.yaml

# Create the Flux Release
flux create helmrelease akv2k8s \
  --interval=5m \
  --release-name=akv2k8s \
  --target-namespace=kube-system \
  --interval=5m \
  --source=HelmRepository/spv-charts \
  --chart=akv2k8s \
  --chart-version=">=2.0.0-0" \
  --crds=CreateReplace \
  --values-from=secret/akv2k8s-values.yaml \
  --export > ./clusters/$ARC_AKS_NAME/akv2k8s-helm.yaml

# Update the Git Repo
git add ./clusters/$ARC_AKS_NAME/akv2k8s-*.yaml && git commit -m "Installing avk2k8s" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl get pods -n kube-system |grep akv2k8s

# Deploy Sample
cat << EOF | kubectl apply --namespace default -f -
---
apiVersion: spv.no/v2beta1
kind: AzureKeyVaultSecret
metadata:
  name: test-secret
  namespace: default
spec:
  vault:
    name: $VAULT_NAME
    object:
      name: admin
      type: secret
  output:
    secret:
      name: akv2k8s-test-secret
      dataKey: admin-password
---
apiVersion: v1
kind: Pod
metadata:
  name: env-test
spec:
  containers:
  - name: envar-demo-container
    image: gcr.io/google-samples/node-hello:1.0
    env:
    - name: MAP_SECRET
      valueFrom:
        secretKeyRef:
          name: akv2k8s-test-secret
          key: admin-password
EOF

# Validate
kubectl exec env-test -- printenv MAP_SECRET
```
