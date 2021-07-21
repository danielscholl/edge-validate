#!/usr/bin/env bash
#
#  Purpose: Deploy Edge Apps Software.
#  Usage:
#    install_edge_app.sh

###############################
## ARGUMENT INPUT            ##
###############################
usage() { echo "Usage: remove.sh " 1>&2; exit 1; }

if [ ! -z $1 ]; then CLUSTER=$1; fi
if [ -z $CLUSTER ]; then
  CLUSTER="dev"
fi

# Check if the parameter given is there or not
if [ -z "$PRINCIPAL_ID" ]; then
    echo "Script cannot run if the PRINCIPAL_ID is not given"
    exit 1
fi

# Check if the parameter given is there or not
if [ -z "$TENANT_ID" ]; then
    echo "Script cannot run if the TENANT_ID character is not given"
    exit 1
fi

# Check if the parameter given is there or not
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Script cannot run if the SUBSCRIPTION_ID character is not given"
    exit 1
fi

# Check if the parameter given is there or not
if [ -z "$VAULT_NAME" ]; then
    echo "Script cannot run if the VAULT_NAME character is not given"
    exit 1
fi


SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  TARGET="$(readlink "$SOURCE")"
  if [[ $TARGET == /* ]]; then
    echo "SOURCE '$SOURCE' is an absolute symlink to '$TARGET'"
    SOURCE="$TARGET"
  else
    DIR="$( dirname "$SOURCE" )"
    echo "SOURCE '$SOURCE' is a relative symlink to '$TARGET' (relative to '$DIR')"
    SOURCE="$DIR/$TARGET" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  fi
done

RDIR="$( dirname "$SOURCE" )"
if [[ $RDIR == '.' ]]; then
  FLUX_DIR="../flux-infra"
else
  FLUX_DIR="flux-infra"
fi

BASE_DIR=$(pwd)
RAND="$(echo $RANDOM | tr '[0-9]' '[a-z]')"

# Create the Branch
BASE_DIR=$(pwd)
cd $FLUX_DIR
git pull origin main
git checkout -b flux_$RAND
cd $BASE_DIR

# Create the Application Base Directory
mkdir -p $FLUX_DIR/apps/base/sample-app

# Create the Flux Helm Release
cat > $FLUX_DIR/apps/base/sample-app/release.yaml <<EOF
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: environment-debug
  namespace: sample-app
spec:
  chart:
    spec:
      chart: ./charts/env-debug
      sourceRef:
        kind: GitRepository
        name: edge-validate
        namespace: flux-system
  interval: 5m0s
  install:
    remediation:
      retries: 3
  targetNamespace: sample-app
  values:
    azure:
      enabled: true
      tenant_id: $TENANT_ID
      subscription_id: $SUBSCRIPTION_ID
      keyvault_name: $VAULT_NAME
    env:
      - name: ADMIN_PASSWORD
        secret:
          name: key-vault-secrets
          key: admin-password
EOF

# Create the Kustomization
cat > $FLUX_DIR/apps/base/sample-app/kustomization.yaml <<EOF
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: sample-app
resources:
  - release.yaml
EOF

# Create the Application Environment Patch Directory
mkdir -p $FLUX_DIR/apps/$CLUSTER

# Create the Namespace
cat > $FLUX_DIR/apps/$CLUSTER/namespace.yaml <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: sample-app
EOF

# Create the KV Credentials Secret
kubectl create secret generic kv-creds \
  --namespace sample-app \
  --from-literal clientid=$PRINCIPAL_ID \
  --from-literal clientsecret=$PRINCIPAL_SECRET \
  --dry-run=client -o yaml| kubeseal -w $FLUX_DIR/apps/$CLUSTER/sample-app-secret.yaml \
    --controller-namespace kube-system \
    --controller-name sealed-secrets \
    --format yaml

# Create Release with Values Set
cat > $FLUX_DIR/apps/$CLUSTER/sample-app-values.yaml <<EOF
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: environment-debug
  namespace: sample-app
spec:
  values:
    message: "Environment is $CLUSTER"
    azure:
      tenant_id: $TENANT_ID
      subscription_id: $SUBSCRIPTION_ID
      keyvault_name: $VAULT_NAME
EOF

# Create the Kustomize Override Patch
cat > $FLUX_DIR/apps/$CLUSTER/kustomization.yaml <<EOF
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: sample-app
resources:
  - namespace.yaml
  - sample-app-secret.yaml
  - ../base/sample-app
patchesStrategicMerge:
  - sample-app-values.yaml
EOF

# Create the Kustomization
flux create kustomization edge-apps \
  --source=flux-system \
  --path=./apps/$CLUSTER \
  --prune=true \
  --interval=5m \
  --depends-on=edge-infra \
  --export > $FLUX_DIR/clusters/$CLUSTER/edge-apps-kustomization.yaml

# Update the Git Repo
BASE_DIR=$(pwd)
cd $FLUX_DIR
git add -f apps/base
git add -f apps/$CLUSTER
git add -f clusters/$CLUSTER/edge-apps-kustomization.yaml
git commit -am "Hookup Apps Kustomization"
git push origin flux_$RAND
gh pr create --title "Application Configuration Management" --body "This PR will deploy all edge-apps software to the $CLUSTER cluster."
git checkout main
git branch -D flux_$RAND
cd $BASE_DIR
