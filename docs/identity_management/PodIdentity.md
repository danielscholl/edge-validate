# Instructions for Setting up Pod Identity

Install AAD Pod Identity in the clusters.
> This process will perform a checkin on the git repository /clusters/`$AKS_NAME`/flux-system

**Technical Links**
[AAD Pod Identity with Kubenet](https://azure.github.io/aad-pod-identity/docs/configure/aad_pod_identity_on_kubenet/)
[AAD Pod Identity Managed Mode](https://azure.github.io/aad-pod-identity/docs/configure/pod_identity_in_managed_mode/)
[Blog](https://opensourcelibs.com/lib/aad-pod-identity)


**Install AAD Pod Identity on the Azure Kubernetes Instance**

This method of installation utilizes flux so gitops should be configured prior to running this step.

```bash
RESOURCE_GROUP="azure-k8s"
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME

# Install AAD Pod Identity (kubenet roles should already be configured)
cat > ./clusters/$AKS_NAME/aad-pod-identity.yaml <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: aad-pod-identity
---
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: HelmRepository
metadata:
  name: aad-pod-identity
  namespace: aad-pod-identity
spec:
  url: https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
  interval: 10m
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: aad-pod-identity
  namespace: aad-pod-identity
spec:
  interval: 5m
  chart:
    spec:
      chart: aad-pod-identity
      version: 4.1.1
      sourceRef:
        kind: HelmRepository
        name: aad-pod-identity
        namespace: aad-pod-identity
      interval: 1m
EOF

# Update the Git Repo
git add ./clusters/$AKS_NAME/aad-pod-identity.yaml && git commit -m "Installing AAD Pod Identity" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl -n aad-pod-identity get pods
```

Create the Identity and Binding

```bash
RESOURCE_GROUP="azure-k8s"
AKS_NAME="azure-k8s"
IDENTITY="test-identity"

# Create POD Identity
az identity create --resource-group ${RESOURCE_GROUP} --name ${IDENTITY}
POD_IDENTITY_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${IDENTITY} --query id -otsv)"
POD_IDENTITY_CLIENT_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${IDENTITY} --query clientId -otsv)"
KUBENET_ID="$(az aks show -g ${RESOURCE_GROUP} -n ${AKS_NAME} --query identityProfile.kubeletidentity.clientId -otsv)"
az role assignment create --role "Managed Identity Operator" --assignee "$KUBENET_ID" --scope $POD_IDENTITY_ID


# Create or Update the AzureIdentity and Binding
# Deploy Test Pod
cat <<EOF | kubectl apply --namespace default -f -
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentity
metadata:
  name: test-identity
  namespace: default
spec:
  type: 0
  resourceID: $POD_IDENTITY_ID
  clientID: $POD_IDENTITY_CLIENT_ID
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentityBinding
metadata:
  name: test-identity-binding
  namespace: default
spec:
  azureIdentity: test-identity
  selector: test-identity
---
apiVersion: v1
kind: Pod
metadata:
  name: identity-test
  labels:
    aadpodidbinding: test-identity
spec:
  containers:
  - name: identity-test
    image: mcr.microsoft.com/oss/azure/aad-pod-identity/demo:v1.6.3
    args:
      - --subscriptionid=$(az account show --query id -otsv)
      - --clientid=${POD_IDENTITY_CLIENT_ID}
      - --resourcegroup=${RESOURCE_GROUP}
    env:
      - name: MY_POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: MY_POD_NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: MY_POD_IP
        valueFrom:
          fieldRef:
            fieldPath: status.podIP
  nodeSelector:
    kubernetes.io/os: linux
EOF

# Validate
kubectl logs identity-test

```


**ARC Enabled Instance**

```bash
ARC_AKS_NAME="kind-k8s"
kubectl config use-context "kind-$ARC_AKS_NAME"

cat > ./clusters/$ARC_AKS_NAME/aad-pod-identity.yaml <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: aad-pod-identity
---
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: HelmRepository
metadata:
  name: aad-pod-identity
  namespace: aad-pod-identity
spec:
  url: https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
  interval: 10m
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: aad-pod-identity
  namespace: aad-pod-identity
spec:
  interval: 5m
  chart:
    spec:
      chart: aad-pod-identity
      version: 4.0.0
      sourceRef:
        kind: HelmRepository
        name: aad-pod-identity
        namespace: aad-pod-identity
      interval: 1m
  values:
    operationMode: managed
    adminsecret:
      tenantID:
      clientID:
      clientSecret:
EOF

# Update the Git Repo
git add ./clusters/$ARC_AKS_NAME/aad-pod-identity.yaml && git commit -m "Installing AAD Pod Identity" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl -n aad-pod-identity get pods
```