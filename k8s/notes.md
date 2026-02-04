
## Deploy python-app

Hoofdstuk 26,27,28


## ArgoCD CLI

https://argo-cd.readthedocs.io/en/stable/cli_installation/

```
brew install argocd
```

## ArgoCD

https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd

```
helm repo add argo https://argoproj.github.io/argo-helm
helm repo ls
```

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
argocd login argocd.test.com --insecure --grpc-web --username ${ARGOCD_USER} --password ${ARGOCD_PASSWORD}
```

## Actions Runner Controller

https://github.com/actions/actions-runner-controller/blob/master/docs/quickstart.md

```
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml

# Generate PAT Github.  LETOP LETOP KIJK NAAR ANDERE VERSIE

# Deploy and configure ARC
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller

helm upgrade --install --namespace actions-runner-system --create-namespace\
  --set=authSecret.create=true\
  --set=authSecret.github_token=${GITHUB_TOKEN} \
  --wait actions-runner-controller actions-runner-controller/actions-runner-controller
```


# Eigen runner

Maak een Dockerfile:

```
FROM ghcr.io/actions/actions-runner:latest

USER root

RUN apt-get update && \
    apt-get install -y \
        python3 \
        python3-pip \
        curl \
        yq \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER runner
```

Bouw image lokaal

```
docker build -t roegema/self-hosted-runner:latest .
```

Login op Dockerhub en push image

```
docker login
docker push roegema/self-hosted-runner:latest
```

Controleer in Docker Hub dat de image er staat:
<https://hub.docker.com/repositories/roegema>

Deploy naar Kubernetes:

```
cat << EOF | kubectl apply -n actions-runner-system -f runnerdeployement.yaml
```

Verify:

```
kubectl exec -it -n actions-runner-system deploy/self-hosted-runners -- bash
