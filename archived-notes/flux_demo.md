
**Technical Links**

[Tutorial 1](https://www.youtube.com/watch?v=N6UCKF7JD7k&t=1004s)

[Tutorial 2](https://www.youtube.com/watch?v=btqZkVQIdd8&t=144s)

[Tutorial 3](https://www.youtube.com/watch?v=wMSswUaN-34)

[Tutorial 4](https://www.youtube.com/watch?v=2oC2pksBGZg)

[Tutorial 5](https://www.youtube.com/watch?v=UhV8kYcb9Mc)


```bash
# Setup Values for Github Access
export GITHUB_TOKEN=<your-token>
export GITHUB_USER=<your-username>
export GITHUB_REPO=flux-infra

### SETUP A DEVELOPMENT CLUSTER ###
kind create cluster --name staging

# Configure and install flux
flux check --pre
flux bootstrap github \
    --context=kind-staging \
    --owner=${GITHUB_USER} \
    --repository=flux-infra \
    --branch=main \
    --personal \
    --path=clusters/staging


# Clone down the new flux repo for the cluster
git clone https://github.com/${GITHUB_USER}/flux-infra.git


#############################################
### Deploy a Sample Application (PodInfo) ###
#############################################

# Configure a Flux Source
flux create source git podinfo \
  --url=https://github.com/stefanprodan/podinfo \
  --branch=master \
  --interval=30s \
  --export > ./flux-infra/clusters/staging/podinfo-source.yaml

# Configure a Flux Kustomization
flux create kustomization podinfo \
  --source=podinfo \
  --path="./kustomize" \
  --prune=true \
  --validation=client \
  --interval=5m \
  --export > ./flux-infra/clusters/staging/podinfo-kustomization.yaml

cd flux-infra && git add -A && git commit -m "Add Pod Info Application" && git push && cd ..

# Validate
flux get kustomizations
kubectl -n default get deployments,services



#################################################
### Deploy a Sample Application (realtimeapp) ###
#################################################

# Deploy Realtime App
flux create source git realtimeapp-infra \
  --url=https://github.com/gbaeke/realtimeapp-infra \
  --branch=master \
  --interval=30s \
  --export > ./flux-infra/clusters/staging/realtimeapp-source.yaml

# Configure a Flux Kustomization
flux create kustomization realtimeapp-dev \
  --namespace=flux-system \
  --source=GitRepository/realtimeapp-infra \
  --path="./deploy/overlays/dev" \
  --prune=true \
  --interval=1m \
  --validation=client \
  --timeout 2m \
  --health-check="Deployment/realtime-dev.realtime-dev" \
  --health-check="Deployment/redis-dev.realtime-dev" \
  --export > ./flux-infra/clusters/staging/realtimeapp-dev.yaml

cd flux-infra && git add -A && git commit -m "Add Real Time App" && git push && cd ..

# Validate
flux get kustomizations
kubectl get all -n realtime-dev
```


```bash
# Cleanup
kubectl config use-context kind-staging
flux uninstall

rm -rf ./flux-infra/clusters/staging
cd flux-infra && git add -A && git commit -m "Removed staging cluster" && git push && cd ..
kind delete clusters staging

# Manually remove the repo.  http://github.com/${GITHUB_USER}/flux-infra
```


*Connect to Production Cluster**
```bash
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME
```
