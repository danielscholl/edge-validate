# Instructions for Setting up Flux

```bash
AKS_NAME="azure-k8s"

# Install Flux CD locally
curl -s https://fluxcd.io/install.sh | sudo bash

# enable completions in ~/.bash_profile
. <(flux completion bash)

# Validate Flux requirements
flux check --pre

# Export Github Information
export GITHUB_TOKEN=<your-token>
export GITHUB_USER=<your-username>
export GITHUB_REPO=<name-of-your-repo>

# Bootstrap Flux Components
flux bootstrap github \
--owner=$GITHUB_USER \
--repository=$GITHUB_REPO \
--branch=main \
--path=./clusters/$AKS_NAME

# Validate
flux check
```