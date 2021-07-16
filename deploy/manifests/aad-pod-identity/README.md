# Instructions

```bash
# Create the Namespace
cat >> aad-pod-identity-ns.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: aad-pod-identity
EOF

# Create the Flux Source
flux create source helm aad-pod-identity \
--interval=5m \
--url=https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts \
--export > aad-pod-identity-source.yaml

# Create a Temporary Values File
cat > values.yaml <<EOF
operationMode: managed
EOF

# Create the Flux Release
flux create helmrelease aad-pod-identity \
--interval=5m \
--release-name=aad-pod-identity \
--target-namespace=kube-system \
--interval=5m \
--source=HelmRepository/aad-pod-identity \
--chart=aad-pod-identity \
--chart-version=">=4.1.0-0" \
--crds=CreateReplace \
--values=values.yaml \
-- export > aad-pod-identity-helm.yaml
&& rm values.yaml

```
