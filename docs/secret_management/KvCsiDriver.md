# Instructions for Azure Key Vault CSI Driver

Install the CSI Driver for Azure Key Vault in the clusters.
> This process will perform a checkin on the git repository /clusters/`$AKS_NAME`/flux-system

**Technical Links**

[Kubecon Session](https://www.youtube.com/watch?v=w0k7MI6sCJg)
[Blog](https://www.linkedin.com/pulse/gitops-part-1-girish-goudar-1c?trk=read_related_article-card_title)


**Install CSI Driver on the Azure Kubernetes Instance**

```bash
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME

cat > ./clusters/$AKS_NAME/csi-driver.yaml <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: csi-driver
---
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: HelmRepository
metadata:
  name: csi-secrets-store-provider-azure
  namespace: flux-system
spec:
  interval: 5m0s
  url: https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: csi-secrets-store-provider-azure
  namespace: flux-system
spec:
  chart:
    spec:
      chart: csi-secrets-store-provider-azure
      sourceRef:
        kind: HelmRepository
        name: csi-secrets-store-provider-azure
      version: 0.0.20
  install: {}
  interval: 5m0s
  targetNamespace: csi-driver
EOF

# Update the Git Repo
git add ./clusters/$AKS_NAME/csi-driver.yaml && git commit -m "Installing KV CSI Driver" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl -n kube-system get pods

