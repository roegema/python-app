## Actions Runner Controller

https://github.com/actions/actions-runner-controller/blob/master/docs/quickstart.md

```
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml

# Generate PAT Github

# Deploy and configure ARC
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller

helm upgrade --install --namespace actions-runner-system --create-namespace\
  --set=authSecret.create=true\
  --set=authSecret.github_token="REPLACE_YOUR_TOKEN_HERE"\
  --wait actions-runner-controller actions-runner-controller/actions-runner-controller
```

## ArgoCD CLI

https://argo-cd.readthedocs.io/en/stable/cli_installation/

```
brew install argocd
```

## ArgoCD

### Configure argocd repo + app
```
# Get admin password:
kubectl get secrets -n argocd argocd-initial-admin-secret -o yaml
# Decode
echo xxxxx== | base64 -d
```

### Use API to login

https://argo-cd.readthedocs.io/en/stable/getting_started/

```
argocd login argocd.test.com --insecure --grpc-web --username admin --password xxxxx
```
