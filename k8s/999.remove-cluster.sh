function cleanup_github_arc() {
  SetHeading "Cleanup Actions Runner Controller"

  # ------------------------------------------
  # 1. Uninstall ARC with Helm (idempotent)
  # ------------------------------------------
  SetInfo "Removing ARC (helm uninstall)..."
  if helm status actions-runner-controller -n actions-runner-system >/dev/null 2>&1; then
    helm uninstall actions-runner-controller -n actions-runner-system
    SetComment "ARC removed via Helm."
  else
    SetComment "ARC Helm release does not exist. Skipping."
  fi

  # ------------------------------------------
  # 2. Delete ARC runner resources (idempotent)
  # ------------------------------------------
  SetInfo "Cleaning ARC runner resources..."
  kubectl delete runners --all -n actions-runner-system >/dev/null 2>&1 || true
  kubectl delete horizontalrunnerautoscalers --all -n actions-runner-system >/dev/null 2>&1 || true
  kubectl delete runnerdeployments --all -n actions-runner-system >/dev/null 2>&1 || true
  kubectl delete runnersets --all -n actions-runner-system >/dev/null 2>&1 || true
  SetComment "ARC CRD resources removed (if present)."

  # ------------------------------------------
  # 3. Delete ARC namespace
  # ------------------------------------------
  if kubectl get namespace actions-runner-system >/dev/null 2>&1; then
    SetComment "Deleting namespace actions-runner-system..."
    kubectl delete namespace actions-runner-system
  else
    SetComment "Namespace actions-runner-system does not exist. Skipping."
  fi

  # ------------------------------------------
  # 4. Optional: Clean up cert-manager namespace
  # ------------------------------------------
  SetInfo "Optionally removing cert-manager..."
  if kubectl get namespace cert-manager >/dev/null 2>&1; then
    kubectl delete namespace cert-manager
    SetComment "cert-manager namespace removed."
  else
    SetComment "cert-manager namespace does not exist. Skipping."
  fi

  # ------------------------------------------
  # 5. Optional: Remove cert-manager CRDs
  # ------------------------------------------
  SetInfo "Removing cert-manager CRDs (idempotent)..."
  kubectl delete crd \
    certificates.cert-manager.io \
    certificaterequests.cert-manager.io \
    clusterissuers.cert-manager.io \
    issuers.cert-manager.io \
    challenges.acme.cert-manager.io \
    orders.acme.cert-manager.io \
    >/dev/null 2>&1 || true
  SetComment "cert-manager CRDs removed (if present)."

  # ------------------------------------------
  # 6. Delete kind cluster (if exists)
  # Pass cluster name as argument: cleanup_github_arc kind-2
  # Default = "kind"
  # ------------------------------------------
  if kind get clusters | grep -q "^${1:-kind}$"; then
    SetInfo "Deleting kind cluster '${1:-kind}'..."
    kind delete cluster --name "${1:-kind}"
    SetComment "Kind cluster deleted."
  else
    SetComment "Kind cluster '${1:-kind}' not found. Skipping."
  fi

  SetHeading "Cleanup complete — GitHub runners will be cleaned up automatically."
}

