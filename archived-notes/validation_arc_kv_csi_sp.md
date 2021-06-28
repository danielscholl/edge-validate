# Validation: ARC - KV CSI Secret Driver with Service Principal

This validation for ARC will use Service Principal and Key Vault CSI Secret Driver features o test secret management with Key Vault Secrets.


Setup the Cluster
```bash
RESOURCE_GROUP="azure-k8s"
LOCATION="eastus"

# Create a Resource Group
az group create -n $RESOURCE_GROUP -l $LOCATION

# Using kind create a Kubernetes Cluster
ARC_AKS_NAME="kind-k8s"
kind create cluster --name $ARC_AKS_NAME

# Arc Enable the Cluster
az connectedk8s connect -n $ARC_AKS_NAME -g $RESOURCE_GROUP

# Arc Enable the Cluster
az connectedk8s connect -n $ARC_AKS_NAME -g $RESOURCE_GROUP

################################
### Setup and Configure Flux ###
################################

# Setup Values for Github Access
export GITHUB_TOKEN=<your-token>
export GITHUB_USER=<your-username>
export GITHUB_REPO=<your-repo>

flux check --pre
flux bootstrap github \
    --context=kind-${ARC_AKS_NAME} \
    --owner=${GITHUB_USER} \
    --repository=${GITHUB_REPO} \
    --branch=main \
    --personal \
    --path=clusters/${ARC_AKS_NAME}


##############################
### Install Sealed Secrets ###
##############################
cat <<EOF | kubectl apply --namespace default -f -
apiVersion: v1
kind: Namespace
metadata:
  name: sealed-secrets
EOF

# Create a Flux Helm Source
flux create source helm sealed-secrets \
  --url https://bitnami-labs.github.io/sealed-secrets \
  --interval 1m

# Create a Flux Helm Repo
flux create helmrelease sealed-secrets \
    --interval=1m \
    --release-name=sealed-secrets \
    --target-namespace=sealed-secrets \
    --source=HelmRepository/sealed-secrets \
    --chart=sealed-secrets \
    --chart-version=">=1.16.0-0" \
    --crds=CreateReplace
```



Setup Key Vault

```bash
# Create Key Vault
VAULT_NAME="$ARC_AKS_NAME-vault"
az keyvault create --name $VAULT_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

# Create a Secret
SECRET_NAME="admin"
SECRET_VALUE="t0p-S3cr3t"
az keyvault secret set --name $SECRET_NAME --value $SECRET_VALUE --vault-name $VAULT_NAME

# Create a Service Principal
IDENTITY_CLIENT_SECRET=$(az ad sp create-for-rbac -n $ARC_AKS_NAME --skip-assignment --query password -o tsv)
IDENTITY_CLIENT_ID=$(az ad sp list --display-name $ARC_AKS_NAME --query [].appId -o tsv)

# Add Access Policy for Service Principal
az keyvault set-policy --name $VAULT_NAME --resource-group $RESOURCE_GROUP --object-id $IDENTITY_CLIENT_ID --key-permissions encrypt decrypt --secret-permissions get --certificate-permissions get
```



```bash
# Create Namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: csi-driver
EOF

# Create a Secret
kubectl create secret generic secrets-store-creds --namespace csi-driver \
  --from-literal clientid=$IDENTITY_CLIENT_ID \
  --from-literal clientsecret=$IDENTITY_CLIENT_SECRET \
  --dry-run=client -o yaml | kubeseal \
    --controller-namespace sealed-secrets  \
    --controller-name sealed-secrets \
    --format yaml | \
    kubectl apply -f -

# Create a Flux Helm Source
flux create source helm csi-secrets-store-provider-azure \
  --url=https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts \
  --interval=5m

# Create a Flux Helm Repo
flux create helmrelease csi-secrets-store-provider-azure  \
  --interval=5m \
  --target-namespace=csi-driver \
  --source=HelmRepository/csi-secrets-store-provider-azure \
  --chart=csi-secrets-store-provider-azure \
  --chart-version="0.0.20" \
  --export

# Validate Secret Exists
kubectl get helmrelease -A
kubectl get pods -n csi-driver
```

Deploy Sample Application

```bash
# Create a Secret
kubectl create secret generic secrets-store-creds --namespace default \
  --from-literal clientid=$IDENTITY_CLIENT_ID \
  --from-literal clientsecret=$IDENTITY_CLIENT_SECRET \
  --dry-run=client -o yaml | kubeseal \
    --controller-namespace sealed-secrets  \
    --controller-name sealed-secrets \
    --format yaml | \
    kubectl apply -f -

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
    usePodIdentity: "false"
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
spec:
  volumes:
    - name: azure-keyvault
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: azure-keyvault
        nodePublishSecretRef:
          name: secrets-store-creds
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

cat <<EOF | kubectl apply --namespace default -f -
---
# This is a sample pod definition for using SecretProviderClass and service-principal to access Keyvault
kind: Pod
apiVersion: v1
metadata:
  name: busybox-secrets-store-inline
spec:
  containers:
  - name: busybox
    image: k8s.gcr.io/e2e-test-images/busybox:1.29
    command:
      - "/bin/sleep"
      - "10000"
    volumeMounts:
    - name: secrets-store-inline
      mountPath: "/mnt/secrets-store"
      readOnly: true
  volumes:
    - name: secrets-store-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "azure-keyvault"
        nodePublishSecretRef:                       # Only required when using service principal mode
          name: secrets-store-creds                 # Only required
EOF

# Validate
kubectl exec vault-test -- ls /mnt/azure-keyvault/
kubectl exec vault-test -- cat /mnt/azure-keyvault/admin
kubectl exec vault-test -- env |grep ADMIN_PASSWORD
