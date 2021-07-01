# Instructions for Azure Key Vault CSI Driver

Install the CSI Driver for Azure Key Vault in the clusters.


**Technical Links**

[Kubecon Session](https://www.youtube.com/watch?v=w0k7MI6sCJg)
[Blog](https://www.linkedin.com/pulse/gitops-part-1-girish-goudar-1c?trk=read_related_article-card_title)
[Blog](https://ahmedkhamessi.com/2020-10-15-Synchronize-Kubernetes-Secrets-AKV/)
[Documentation](https://docs.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)


**Install CSI Driver on the Azure Kubernetes Instance**

```bash
AKS_NAME="azure-k8s"
kubectl config use-context $AKS_NAME

# Create the Flux Source
flux create source helm kv-csi-driver \
--interval=5m \
--url=https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts \
--export > ./clusters/$AKS_NAME/kv-csi-driver-source.yaml

# Create the Flux Helm Release (0.0.19 works for Secret Object Mapping)
flux create helmrelease kv-csi-driver \
--interval=5m \
--release-name=kv-csi-driver \
--target-namespace=kube-system \
--interval=5m \
--source=HelmRepository/kv-csi-driver \
--chart=csi-secrets-store-provider-azure \
--chart-version="0.0.19" \
--export > ./clusters/$AKS_NAME/kv-csi-driver-helm.yaml

# Update the Git Repo
git add ./clusters/$AKS_NAME/kv-csi-driver-*.yaml && git commit -m "Installing KV CSI Driver" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl get pods -n kube-system |grep kv-csi-driver
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


**ARC Enabled Instance**

```bash
ARC_AKS_NAME="kind-k8s"
kubectl config use-context kind-$ARC_AKS_NAME

# Create the Flux Source
flux create source helm kv-csi-driver \
--interval=5m \
--url=https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts \
--export > ./clusters/$ARC_AKS_NAME/kv-csi-driver-source.yaml

# Create the Flux Helm Release (0.0.19 works for Secret Object Mapping)
flux create helmrelease kv-csi-driver \
--interval=5m \
--release-name=kv-csi-driver \
--target-namespace=kube-system \
--interval=5m \
--source=HelmRepository/kv-csi-driver \
--chart=csi-secrets-store-provider-azure \
--chart-version="0.0.19" \
--export > ./clusters/$ARC_AKS_NAME/kv-csi-driver-helm.yaml

# Update the Git Repo
git add ./clusters/$ARC_AKS_NAME/kv-csi-driver-*.yaml && git commit -m "Installing KV CSI Driver" && git push

# Validate the Deployment
flux reconcile kustomization flux-system --with-source
kubectl get helmrelease -A
kubectl get pods -n kube-system |grep kv-csi-driver
```

Deploy a Sample

> Requires Sealed Secrets and KV_PRINCIPAL created

```bash
# Create a Sealed Secret using the key
kubectl create secret generic kv-creds \
  --from-literal clientid=$KV_PRINCIPAL_ID \
  --from-literal clientsecret=$KV_PRINCIPAL_SECRET \
  --dry-run=client -o yaml| kubeseal \
    --cert=./clusters/$ARC_AKS_NAME/pub-cert.pem \
    --format yaml | kubectl apply --namespace default -f -

# Deploy SecretProviderClass and Test POD
cat <<EOF | kubectl apply --namespace default -f -
---
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"         # [OPTIONAL] if not provided, will default to "false"
    keyvaultName: "$VAULT_NAME"     # the name of the KeyVault
    cloudName: ""                   # [OPTIONAL for Azure] if not provided, azure environment will default to AzurePublicCloud
    objects:  |
      array:
        - |
          objectName: admin
          objectType: secret        # object types: secret, key or cert
          objectVersion: ""         # [OPTIONAL] object versions, default to latest if empty
    tenantId: "$TENANT_ID"
  secretObjects:
  - secretName: key-vault-secrets
    type: Opaque
    data:
    - objectName: admin
      key: admin-password
---
apiVersion: v1
kind: Pod
metadata:
  name: vault-test
  namespace: default
spec:
  volumes:
    - name: azure-keyvault
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: azure-keyvault
        nodePublishSecretRef:
          name: kv-creds
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
kubectl exec vault-test -- ls /mnt/azure-keyvault
kubectl exec vault-test -- cat /mnt/azure-keyvault/admin
kubectl exec vault-test -- env |grep ADMIN_PASSWORD
```
