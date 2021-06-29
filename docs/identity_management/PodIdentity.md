# Instructions for Setting up Pod Identity

Install AAD Pod Identity in the clusters.
> This process will perform a checkin on the git repository /clusters/`$AKS_NAME`/flux-system

**Technical Links**
[AAD Pod Identity with Kubenet](https://azure.github.io/aad-pod-identity/docs/configure/aad_pod_identity_on_kubenet/)
[AAD Pod Identity Managed Mode](https://azure.github.io/aad-pod-identity/docs/configure/pod_identity_in_managed_mode/)
[Blog](https://opensourcelibs.com/lib/aad-pod-identity)
[Issue 380](https://github.com/Azure/aad-pod-identity/issues/380)
[Best Practices](https://docs.microsoft.com/en-us/azure/aks/operator-best-practices-identity)


**Install AAD Pod Identity on the Azure Kubernetes Instance**

This method of installation utilizes flux so gitops should be configured prior to running this step.

```bash
RESOURCE_GROUP="azure-k8s"
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME

# Install AAD Pod Identity (kubenet roles should already be configured)
# Create the Flux Source
flux create source helm aad-pod-identity \
  --interval=5m \
  --url=https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts \
  --export > ./clusters/$AKS_NAME/aad-pod-identity-source.yaml

# Create the Flux Helm Release (0.0.19 works for Secret Object Mapping)
flux create helmrelease aad-pod-identity \
  --interval=5m \
  --release-name=aad-pod-identity \
  --target-namespace=kube-system \
  --interval=5m \
  --source=HelmRepository/aad-pod-identity \
  --chart=aad-pod-identity \
  --chart-version="4.1.1" \
  --export > ./clusters/$AKS_NAME/aad-pod-identity-helm.yaml

# Update the Git Repo
git add ./clusters/$AKS_NAME/aad-pod-identity-*.yaml && git commit -m "Installing AAD Pod Identity" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrepository -A
kubectl get helmrelease -A
helm list -A
kubectl -n kube-system get pods |grep aad-pod-identity
```

Create the Identity and Binding

```bash
RESOURCE_GROUP="azure-k8s"
AKS_NAME="azure-k8s"
IDENTITY="test-identity"

# Create a test Managed Identity
az identity create --resource-group $RESOURCE_GROUP --name $IDENTITY

# Assign a Role
POD_IDENTITY_ID="$(az identity show -g $RESOURCE_GROUP -n $IDENTITY --query id -otsv)"
POD_IDENTITY_CLIENT_ID="$(az identity show -g $RESOURCE_GROUP -n $IDENTITY --query clientId -otsv)"
KUBENET_ID="$(az aks show -g $RESOURCE_GROUP -n $AKS_NAME --query identityProfile.kubeletidentity.clientId -otsv)"
az role assignment create --role "Managed Identity Operator" --assignee "$KUBENET_ID" --scope $POD_IDENTITY_ID


# Create the AzureIdentity and Binding and deploy a test pod
cat <<EOF | kubectl apply -f -
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

# Validate  (takes about 2 minutes)
kubectl logs identity-test
```


**ARC Enabled Instance**

```bash
ARC_AKS_NAME="kind-k8s"
kubectl config use-context "kind-$ARC_AKS_NAME"

# Create a Service Principal
PRINCIPAL_NAME=$ARC_AKS_NAME-pod-identity-principal
PRINCIPAL_SECRET=$(az ad sp create-for-rbac -n $PRINCIPAL_NAME --skip-assignment --query password -o tsv)
PRINCIPAL_ID=$(az ad sp list --display-name $PRINCIPAL_NAME --query [].appId -o tsv)
TENANT_ID=$(az account show --query tenantId -otsv)
SUBSCRIPTION_ID=$(az account show --query id -otsv)

# Deploy AAD Pod Identity
flux create source helm aad-pod-identity \
--interval=5m \
--url=https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts \
--export > ./clusters/$ARC_AKS_NAME/aad-pod-identity-source.yaml

cat > values.yaml <<EOF
operationMode: managed
EOF

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
--export > ./clusters/$ARC_AKS_NAME/aad-pod-identity-helm.yaml && rm values.yaml

# Update the Git Repo
git add ./clusters/$ARC_AKS_NAME/aad-pod-identity-*.yaml && git commit -m "Installing AAD Pod Identity" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrepository -A
kubectl get pods -n kube-system |grep aad-pod-identity-nmi
```

Deploy a Sample

> Requires Sealed Secrets to be setup first.

```bash
# Create a Sealed Secret using the key
kubectl create secret generic $PRINCIPAL_NAME-creds \
  --from-literal clientsecret=$PRINCIPAL_SECRET --dry-run=client -o yaml| kubeseal \
    --cert=./clusters/$ARC_AKS_NAME/pub-cert.pem \
    --format yaml | kubectl apply --namespace default -f -

# Deploy Azure Identity
cat <<EOF | kubectl apply -f -
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: identity-test
spec:
  type: 1
  tenantID: $TENANT_ID
  clientID: $PRINCIPAL_ID
  clientPassword: {"name":"$PRINCIPAL_NAME-creds","namespace":"default"}
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: identity-test-binding
spec:
  azureIdentity: "identity-test"
  selector: "identity-test"
EOF

# Validate
kubectl run azure-cli -it \
  --rm \
  --image=mcr.microsoft.com/azure-cli \
  --labels=aadpodidbinding=identity-test \
  --command -- \
      curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' \
        -s -H Metadata:true | jq .
```
