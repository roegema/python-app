#!/usr/bin/env bash
##################################################################
# Author: Rene Oegema
# Date: 02-20-2026
# Version: 0.1
# Description: Script to setup a kind cluster with additional k8s actions
# Used by course on https://www.udemy.com/course/from-devops-to-platform-engineering-master-backstage-idps/
##################################################################

#-----------------------------------------------------------------
# GLOBAL VARIABLES
#-----------------------------------------------------------------
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PARENT_DIR="$(cd ${SCRIPT_DIR} && cd ../ && pwd)"
CLUSTER_NAME="backstage"
KIND_CLUSTER="kind-${CLUSTER_NAME}"
GITHUB_APP_REPO="https://github.com/roegema/python-app.git"
SECRETS_FILE="${PARENT_DIR}/__secrets/tokens.sh"
DEBUG_ON="yes"

# Colors
readonly COLOR_NC="\e[0m"
readonly COLOR_RED="\e[1;31m"
readonly COLOR_GREEN="\e[0;32m"
readonly COLOR_YELLOW="\e[1;33m"
readonly COLOR_BLUE="\e[1;34m"
readonly COLOR_MAGENTA="\e[1;35m"
readonly COLOR_CYAN="\e[1;36m"

source ${SECRETS_FILE}

#-----------------------------------------------------------------
# FUNCTIONS
#-----------------------------------------------------------------
function SetTopHeading() {
  printf $COLOR_MAGENTA
  echo -e ""
  echo -e "========================================================================================="
  echo -e "${1^^}"
  echo -e "========================================================================================="
  printf $COLOR_NC
}
function SetHeading() {
  printf $COLOR_YELLOW
  echo -e ""
  echo -e "----------------------------------------------------------------------------------------"
  echo -e "${1}"
  echo -e "----------------------------------------------------------------------------------------"
  printf $COLOR_NC
}
function SetComment() {
  printf $COLOR_GREEN
  echo -e "* ${1}"
  printf $COLOR_NC
}
function SetComment2() {
  echo -e "  - ${1}"
}
function SetComment3() {
  echo -e "    -> ${1}"
}
function SetDebug() {
  if [ "${DEBUG_ON}" == "yes" ]; then
    printf $COLOR_BLUE
    echo -e "[DEBUG] ${1}"
    printf $COLOR_NC
  fi
}
function SetError() {
  printf $COLOR_RED
  echo -e "[ERROR] ${1}"
  printf $COLOR_NC
}
function SetWarning() {
  printf $COLOR_YELLOW
  echo -e "[WARNING] ${1}"
  printf $COLOR_NC
}
function SetInfo() {
  echo -e "[INFO] ${1}"
}

# Stop all other kind clusters except the one in $CLUSTER_NAME
function stop_other_kind_clusters() {
  SetHeading "Stopping all other kind clusters"

  # Ensure CLUSTER_NAME is set
  if [[ -z "${CLUSTER_NAME:-}" ]]; then
    SetError "CLUSTER_NAME is not set. Cannot continue."
    return 1
  fi

  # List all clusters known by kind
  ALL_CLUSTERS=$(kind get clusters 2>/dev/null | tr -d '\r')

  for cluster in $ALL_CLUSTERS; do
    if [[ "$cluster" == "$CLUSTER_NAME" ]]; then
      SetComment "Kind cluster '$cluster' is the target cluster. Not stopping."
      continue
    fi

    SetInfo "Stopping Kind cluster: $cluster"

    # Get node container names for this cluster (exact, no prefix ambiguity)
    NODES=$(kind get nodes --name "$cluster" 2>/dev/null || true)

    if [[ -z "$NODES" ]]; then
      SetComment "No nodes found for cluster '$cluster'. Skipping."
      continue
    fi

    # Stop each node container
    for node in $NODES; do
      SetComment "Stopping node container: $node"
      docker stop "$node" >/dev/null 2>&1 || true
    done
  done
}

function create_kind_cluster() {
  SetHeading "Create cluster"
  # Check if the cluster already exists.
  # "kind get clusters" returns only cluster names, one per line.
  # The '^$' anchors ensure an exact match and prevent partial matches.
  SetInfo "Check existence cluster"
  if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    SetComment "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
    # Show cluster info using the correct context name.
    kubectl cluster-info --context "${KIND_CLUSTER}"
    return 0
  fi
  SetComment "Cluster '${CLUSTER_NAME}' does not exist. Creating..."

  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
EOF
}

function install_nginx_controller() {
  SetHeading "Install nginx controller"
  # Check if the ingress-nginx controller is already installed.
  # If the Deployment exists, we assume installation is complete.
  if kubectl -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
    SetComment "Ingress-nginx controller already installed. Skipping installation."
    kubectl -n ingress-nginx get all
    return 0
  fi

  SetComment "Ingress-nginx controller not found. Installing..."

  # Apply the official manifest for kind
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

  SetComment "Waiting for the ingress-nginx namespace to be created..."
  kubectl wait \
    --for=condition=Established \
    --timeout=60s \
    crd/ingressclasses.networking.k8s.io \
    2>/dev/null

  SetComment "Waiting for the controller Deployment to become ready..."
  kubectl rollout status \
    deployment/ingress-nginx-controller \
    --namespace ingress-nginx \
    --timeout=180s

  SetComment "Waiting for controller Pods to become Ready..."
  kubectl wait \
    --namespace ingress-nginx \
    --for=condition=Ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=180s

  SetInfo "Ingress-nginx controller successfully installed:"
  kubectl -n ingress-nginx get all
}

function deploy_actions_runner_controller() {
  SetHeading "Deploy actions-runners-controller"
  # ------------------------------------------
  # Install cert-manager idempotently
  # ------------------------------------------
  SetInfo "Checking cert-manager installation"
  if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
    SetComment "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml
  else
    SetComment "cert-manager already installed. Skipping."
  fi
  # ------------------------------------------
  # WAIT for cert-manager pods to be READY
  # ------------------------------------------
  SetInfo "Waiting for cert-manager pods to become Ready..."
  # 180s timeout = 36 cycles x 5 seconds
  for i in {1..36}; do
    NOT_READY=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null \
      | awk '$2 !~ /1\/1/ || $3 != "Running"')

    if [[ -z "$NOT_READY" ]]; then
      SetComment "cert-manager pods are Ready."
      break
    fi
    SetComment "cert-manager not ready yet... waiting 5s"
    sleep 5
  done
  # Final check
  NOT_READY=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null \
      | awk '$2 !~ /1\/1/ || $3 != "Running"')

  if [[ -n "$NOT_READY" ]]; then
    SetError "cert-manager did not become ready within timeout."
    kubectl get pods -n cert-manager
    return 1
  fi
  # ------------------------------------------
  # Validate GITHUB_TOKEN exists
  # ------------------------------------------
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    SetError "GITHUB_TOKEN environment variable not set!"
    echo "Export it first: export GITHUB_TOKEN=xxxx"
    return 1
  fi
  # ------------------------------------------
  # Create namespace for ARC if needed
  # ------------------------------------------
  SetInfo "Create namespace if needed"
  if ! kubectl get namespace actions-runner-system >/dev/null 2>&1; then
    SetComment "Creating namespace actions-runner-system..."
    kubectl create namespace actions-runner-system
  else
    SetComment "Namespace actions-runner-system already exists. Skipping."
  fi
  # ------------------------------------------
  # Add helm repo idempotently
  # ------------------------------------------
  SetInfo "Adding Helm repo for ARC"
  helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller >/dev/null 2>&1 \
    || SetComment "Helm repo already exists."
  helm repo update
  # ------------------------------------------
  # Deploy / upgrade ARC idempotently
  # ------------------------------------------
  SetInfo "Deploying / upgrading Actions Runner Controller"
  helm upgrade --install actions-runner-controller \
    actions-runner-controller/actions-runner-controller \
    --namespace actions-runner-system \
    --set=authSecret.create=true \
    --set=authSecret.github_token="${GITHUB_TOKEN}" \
    --wait
  SetComment "Actions Runner Controller deployment complete."
}

function deploy_self_hosted_runners() {
  SetHeading "Deploy self-hosted-runners"
  cat << EOF | kubectl apply -n actions-runner-system -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: self-hosted-runners
spec:
  replicas: 1
  template:
    spec:
      repository: roegema/python-app
EOF
  SetInfo "Show pods in namespace 'actions-runner-system'"
  kubectl get pods -n actions-runner-system
}

function install_argocd() {
  # https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd
  SetHeading "Install ArgoCD"
  # ------------------------------------------
  # 1. Add Helm repo (idempotent)
  # ------------------------------------------
  SetInfo "Adding Helm repository for ArgoCD..."
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || \
    SetComment "Argo Helm repo already exists."
  helm repo update
  # ------------------------------------------
  # 2. Install/upgrade ArgoCD via Helm
  # ------------------------------------------
  SetInfo "Installing ArgoCD via Helm (idempotent)..."
  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --wait \
    -f ${PARENT_DIR}/charts/argocd/values-argo.yaml
  SetComment "ArgoCD Helm deployment completed."
  # ------------------------------------------
  # 3. Wait until ArgoCD pods are all Ready
  # ------------------------------------------
  SetInfo "Waiting for ArgoCD pods to become Ready..."
  for i in {1..30}; do
    NOT_READY=""
    # Loop through all pods in the argocd namespace
    for POD in $(kubectl get pods -n argocd -o name); do
      PHASE=$(kubectl get -n argocd $POD -o jsonpath='{.status.phase}')
      READY=$(kubectl get -n argocd $POD -o jsonpath='{.status.containerStatuses[*].ready}')
      # If pod is not Running OR any container is not ready
      if [[ "$PHASE" != "Running" || "$READY" != "true" ]]; then
        NOT_READY="yes"
        break
      fi
    done
    if [[ -z "$NOT_READY" ]]; then
      SetComment "All ArgoCD pods are Ready."
      break
    fi
    SetComment "ArgoCD not ready yet... waiting 3s"
    sleep 3
  done
  # Final timeout check
  if [[ -n "$NOT_READY" ]]; then
    SetError "ArgoCD pods did not become ready within timeout."
    kubectl get pods -n argocd
    return 1
  fi
  ------------------------------------------
  4. Retrieve ArgoCD admin password
  ------------------------------------------
  SetInfo "Retrieving ArgoCD admin password..."
  ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 --decode 2>/dev/null)
  if [[ -z "$ADMIN_PASSWORD" ]]; then
    SetError "Could not retrieve ArgoCD admin password."
    return 1
  fi
  SetComment "Admin password retrieved."
  # ------------------------------------------
  # 5. Write admin user and password to the secrets file
  # ------------------------------------------
  {
    echo ""
    echo "# Auto-generated ArgoCD admin token (cluster ${KIND_CLUSTER})"
    echo "ARGOCD_USER=\"admin\""
    echo "ARGOCD_PASSWORD=\"${ADMIN_PASSWORD}\""
  } >> "$SECRETS_FILE"
  SetInfo "Admin password written to: $SECRETS_FILE"
  source $SECRETS_FILE
}

create_app_in_argocd() {
  SetHeading "Create python-app in ArgoCD"
  SetInfo "Register python-app git repo"
  argocd login argocd.test.com --insecure --grpc-web --username ${ARGOCD_USER} --password ${ARGOCD_PASSWORD}
  SetComment "Git repo: ${GITHUB_APP_REPO}"
  argocd repo add ${GITHUB_APP_REPO}
  SetInfo "Create application"
  cat << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: python-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${GITHUB_APP_REPO}
    path: charts/python-app
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: python
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
}

#-----------------------------------------------------------------
# MAIN
#-----------------------------------------------------------------
clear
SetTopHeading "Setup kind cluster '${CLUSTER_NAME}'"
cd ${SCRIPT_DIR}

# stop_other_kind_clusters

# create_kind_cluster

# SetInfo "Set kubectl context"
# kubectl config use-context ${KIND_CLUSTER}

# install_nginx_controller

# deploy_actions_runner_controller

# deploy_self_hosted_runners

# install_argocd

create_app_in_argocd
