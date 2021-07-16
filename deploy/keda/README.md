# Instructions

```bash
# Create the Namespace
cat >> keda-ns.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: keda
EOF

# Create the Flux Source
flux create source helm keda-repo \
  --interval=5m \
  --url=https://kedacore.github.io/charts \
  --export > keda-source.yaml

# Create the Flux Release
flux create helmrelease keda \
  --interval=5m \
  --release-name=keda \
  --target-namespace=keda \
  --interval=5m \
  --source=HelmRepository/keda-repo \
  --chart=keda \
  --chart-version="2.0.0" \
  -- export > keda-helm.yaml

```
