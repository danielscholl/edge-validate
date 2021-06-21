# Instructions

```bash
cat >> common/deploy/csidriver/csi-driver-ns.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: csi-driver
EOF

flux create source helm csi-secrets-store-provider-azure \
  --url=https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts \
  --interval=5m \
  --export \
    > common/deploy/csidriver/csi-secrets-source.yaml


flux create hr csi-secrets-store-provider-azure  \
  --interval=5m \
  --target-namespace=csi-driver \
  --source=HelmRepository/csi-secrets-store-provider-azure \
  --chart=csi-secrets-store-provider-azure \
  --chart-version="0.0.20" \
  --export > common/deploy/csidriver/csi-driver-helm.yaml

```


apiVersion: helm.fluxcd.io/v1
kind: HelmRelease
metadata:
  annotations:
    flux.weave.works/automated: "false"
    flux.weave.works/ignore: "true"
  name: csi-secrets-store-provider-azure
  namespace: admin
spec:
  chart:
    name: csi-secrets-store-provider-azure
    repository: https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts/
    version: 0.0.11
  releaseName: csi-secrets-store-provider-azure
  values:
    secrets-store-csi-driver:
      linux:
        metricsAddr: :8090