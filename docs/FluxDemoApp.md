# Instructions for Deploying a Demo App using Flux

```bash
AKS_NAME="azure-k8s"

# Create a kustomization
flux create kustomization demoapp \
  --namespace=flux-system \
  --source=flux-system \
  --path="./manifests" \
  --prune=true \
  --validation=client \
  --interval=5m \
  --export > ./clusters/$AKS_NAME/demoapp-kustomization.yaml

# Create a manifest deployment
mkdir manifests
cat > ./manifests/namespace.yaml <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: demoapp
EOF

cat > ./manifests/deployment.yaml <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demoapp
  namespace: demoapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demoapp
  template:
    metadata:
      labels:
        app: demoapp
    spec:
      containers:
        - name: demoapp
          image: "mcr.microsoft.com/dotnet/core/samples:aspnetapp"
          ports:
            - containerPort: 80
              protocol: TCP
EOF

cat > ./manifests/service.yaml <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: demoapp
  namespace: demoapp
spec:
  type: ClusterIP
  selector:
    app: demoapp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
EOF
```