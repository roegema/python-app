cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    # Label de node zodat de ingress-controller hierop gepland kan worden
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    # Map hostpoorten 80/443 naar de control-plane container
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
        # listenAddress kun je evt. toevoegen, standaard is 0.0.0.0
        # listenAddress: "127.0.0.1"
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
EOF

# Installeer de Ingress-NGINX controller (Kind provider)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wacht tot de controller klaar is
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Check
kubectl -n ingress-nginx get all
