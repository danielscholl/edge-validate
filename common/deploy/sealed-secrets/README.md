# Instructions

```bash
cat >> sealed-secrets-ns.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: sealed-secrets
EOF

flux create source helm sealed-secrets \
    --url https://bitnami-labs.github.io/sealed-secrets \
    --interval 1m \
    --export \
    > common/deploy/sealed-secrets/sealed-secrets-source.yaml

flux create helmrelease sealed-secrets \
    --interval=1m \
    --release-name=sealed-secrets \
    --target-namespace=sealed-secrets \
    --source=HelmRepository/sealed-secrets \
    --chart=sealed-secrets \
    --chart-version=">=1.16.0-0" \
    --crds=CreateReplace \
    --export \
    > common/deploy/sealed-secrets/sealed-secrets-helm.yaml
```