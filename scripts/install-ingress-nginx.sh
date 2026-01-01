#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== NGINX Ingress Controller Installation ===${NC}\n"

# Configuration
INGRESS_NGINX_VERSION="v1.11.3"
NAMESPACE="ingress-nginx"
HTTP_NODEPORT="30487"
HTTPS_NODEPORT="30356"

# Check if already installed
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${YELLOW}Namespace $NAMESPACE already exists${NC}"
    read -p "Do you want to reinstall? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi
    echo -e "${YELLOW}Removing existing installation...${NC}"
    kubectl delete namespace "$NAMESPACE" --wait=true || true
    sleep 5
fi

# Apply base manifest
echo -e "${GREEN}Deploying NGINX Ingress Controller ${INGRESS_NGINX_VERSION}...${NC}"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${INGRESS_NGINX_VERSION}/deploy/static/provider/baremetal/deploy.yaml"

# Wait for deployment to be created
echo -e "${GREEN}Waiting for ingress-nginx controller to be created...${NC}"
kubectl wait --namespace "$NAMESPACE" \
    --for=condition=available \
    --timeout=300s \
    deployment/ingress-nginx-controller || true

# Patch service to use specific NodePorts
echo -e "${GREEN}Configuring NodePorts (HTTP: $HTTP_NODEPORT, HTTPS: $HTTPS_NODEPORT)...${NC}"
kubectl patch service ingress-nginx-controller \
    -n "$NAMESPACE" \
    --type='json' \
    -p="[
        {\"op\": \"replace\", \"path\": \"/spec/ports/0/nodePort\", \"value\": $HTTP_NODEPORT},
        {\"op\": \"replace\", \"path\": \"/spec/ports/1/nodePort\", \"value\": $HTTPS_NODEPORT}
    ]"

# Wait for pods to be ready
echo -e "${GREEN}Waiting for ingress-nginx pods to be ready...${NC}"
kubectl wait --namespace "$NAMESPACE" \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s

# Display status
echo -e "\n${GREEN}=== Installation Complete ===${NC}\n"
kubectl get all -n "$NAMESPACE"

echo -e "\n${GREEN}=== Ingress Controller Service ===${NC}"
kubectl get svc -n "$NAMESPACE" ingress-nginx-controller

echo -e "\n${GREEN}=== IngressClass ===${NC}"
kubectl get ingressclass

echo -e "\n${GREEN}NodePorts configured:${NC}"
echo -e "  HTTP:  ${GREEN}$HTTP_NODEPORT${NC}"
echo -e "  HTTPS: ${GREEN}$HTTPS_NODEPORT${NC}"

echo -e "\n${GREEN}Access the ingress controller at:${NC}"
CONTROL_PLANE_IP=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo -e "  HTTP:  http://${CONTROL_PLANE_IP}:${HTTP_NODEPORT}"
echo -e "  HTTPS: https://${CONTROL_PLANE_IP}:${HTTPS_NODEPORT}"

echo -e "\n${GREEN}Installation successful!${NC}"
