# Instructions for Azure Key Vault CSI Driver

Install the CSI Driver for Azure Key Vault in the clusters.
> This process will perform a checkin on the git repository /clusters/`$AKS_NAME`/flux-system

**Technical Links**

[Kubecon Session](https://www.youtube.com/watch?v=w0k7MI6sCJg)
[Blog](https://www.linkedin.com/pulse/gitops-part-1-girish-goudar-1c?trk=read_related_article-card_title)
[Blog](https://ahmedkhamessi.com/2020-10-15-Synchronize-Kubernetes-Secrets-AKV/)
[Documentation](https://docs.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)


**Install CSI Driver on the Azure Kubernetes Instance**

```bash
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME

#########
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
  namespace: csi-driver
spec:
  interval: 5m0s
  url: https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: csi-secrets-store-provider-azure
  namespace: csi-driver
spec:
  chart:
    spec:
      chart: csi-secrets-store-provider-azure
      sourceRef:
        kind: HelmRepository
        name: csi-secrets-store-provider-azure
      version: 0.0.19
  install: {}
  interval: 5m0s
  targetNamespace: csi-driver
EOF

# Update the Git Repo
git add ./clusters/$AKS_NAME/csi-driver.yaml && git commit -m "Installing KV CSI Driver" && git push
flux reconcile kustomization flux-system --with-source

# Validate the Deployment
kubectl get helmrelease -A
flux get sources helm -A
flux get helmreleases -A
kubectl -n csi-driver get pods
```

Create a pod identity to access the Key Vault Secrets

```bash
KV_IDENTITY_NAME="kv-access-identity"
KV_IDENTITY_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${KV_IDENTITY_NAME} --query id -otsv)"
KV_IDENTITY_CLIENT_ID="$(az identity show -g ${RESOURCE_GROUP} -n ${KV_IDENTITY_NAME} --query clientId -otsv)"
KUBENET_ID="$(az aks show -g ${RESOURCE_GROUP} -n ${AKS_NAME} --query identityProfile.kubeletidentity.clientId -otsv)"


# Create the Pod Identity and Binding
cat <<EOF | kubectl apply --namespace default -f -
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentity
metadata:
  name: kv-access-identity
  namespace: default
spec:
  clientID: $KV_IDENTITY_CLIENT_ID
  resourceID: $KV_IDENTITY_ID
  type: 0 # user-managed identity
---
apiVersion: aadpodidentity.k8s.io/v1
kind: AzureIdentityBinding
metadata:
  name: kv-access-identity-binding
  namespace: default
spec:
  azureIdentity: kv-access-identity
  selector: kv-access-identity
EOF


# Validate the Deployment
kubectl get AzureIdentity -A
kubectl get AzureIdentityBinding -A
```

Add a Secret Provider Class

```bash
TENANT_ID=$(az account show --query tenantId -otsv)
VAULT_NAME="azure-k8s-vault"
KV_IDENTITY_NAME="kv-access-identity"

# Deploy Secret Provider Class
cat <<EOF | kubectl apply --namespace default -f -
---
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    usePodIdentity: "true"
    keyvaultName: "$VAULT_NAME"
    tenantId: "$TENANT_ID"
    objects:  |
      array:
        - |
          objectName: admin
          objectType: secret
  secretObjects:
  - secretName: key-vault-secrets
    type: Opaque
    data:
    - objectName: admin
      key: admin-password
EOF

# Deploy Test Pod
cat <<EOF | kubectl apply --namespace default -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: vault-test
  namespace: default
  labels:
    aadpodidbinding: $KV_IDENTITY_NAME
spec:
  volumes:
    - name: azure-keyvault
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: azure-keyvault
  containers:
    - image: gcr.io/kuar-demo/kuard-amd64:1
      name: kuard
      ports:
        - containerPort: 8080
          name: http
          protocol: TCP
      volumeMounts:
        - name: azure-keyvault
          mountPath: "/mnt/azure-keyvault"
          readOnly: true
      env:
        - name: ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: key-vault-secrets
              key: admin-password
EOF

# Validate
kubectl exec vault-test -- ls /mnt/azure-keyvault/
kubectl exec vault-test -- cat /mnt/azure-keyvault/admin
kubectl exec vault-test -- env |grep ADMIN_PASSWORD
```
