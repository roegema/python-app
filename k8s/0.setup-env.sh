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
CLUSTER_NAME="kind-2"

DEBUG_ON="yes"

# Colors
readonly COLOR_NC="\e[0m"
readonly COLOR_RED="\e[1;31m"
readonly COLOR_GREEN="\e[0;32m"
readonly COLOR_YELLOW="\e[1;33m"
readonly COLOR_BLUE="\e[1;34m"
readonly COLOR_MAGENTA="\e[1;35m"
readonly COLOR_CYAN="\e[1;36m"

source ${PARENT_DIR}/__secrets/tokens.sh

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
SetError() {
  printf $COLOR_RED
  echo -e "[ERROR] ${1}"
  printf $COLOR_NC
}
SetWarning() {
  printf $COLOR_YELLOW
  echo -e "[WARNING] ${1}"
  printf $COLOR_NC
}
SetInfo() {
  echo -e "[INFO] ${1}"
}

function create_kind_cluster() {
local CLUSTER_NAME=${1:-"$CLUSTER_NAME"}
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
  kubectl cluster-info --context kind-${CLUSTER_NAME}
}


function create_kind_cluster() {
  SetHeading "Create cluster"
  # Stop current cluster kind-kind
  SetInfo "Stop current cluster kind-kind (start with command: 'docker start kind-control-plane kind-worker')"
  docker stop kind-control-plane kind-worker
  # Check if the cluster already exists.
  # "kind get clusters" returns only cluster names, one per line.
  # The '^$' anchors ensure an exact match and prevent partial matches.
  SetInfo "Check existence cluster"
  if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    SetComment "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
    # Show cluster info using the correct context name.
    kubectl cluster-info --context "kind-${CLUSTER_NAME}"
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

function deploy_actions_runners() {
  SetHeading "Deploy Github action-runners-controller"
  helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
  helm upgrade --install --namespace actions-runner-system --create-namespace\
    --set=authSecret.create=true\
    --set=authSecret.github_token="${GITHUB_TOKEN}"\
    --wait actions-runner-controller actions-runner-controller/actions-runner-controller
}

#-----------------------------------------------------------------
# MAIN
#-----------------------------------------------------------------
clear
SetTopHeading "Setup kind cluster '${CLUSTER_NAME}'"
cd ${SCRIPT_DIR}

create_kind_cluster
SetInfo "Set kubectl context"
kubectl config use-context kind-${CLUSTER_NAME}

install_nginx_controller

deploy_actions_runners



# echo $ARGOCD_PASSWORD
