#!/bin/bash

# Quick deployment test - only Pulumi part
CONFIG_FILE="configs/enfyra-backend.yaml"

echo "🚀 Quick deployment test..."

# Parse config
echo "📋 Parsing YAML configuration..." 
PROJECT_NAME=$(yq '.application.name' "$CONFIG_FILE")
APP_NAME=$(yq '.kubernetes.deployment.app_name // .application.name' "$CONFIG_FILE")
IMAGE="$PROJECT_NAME:latest"
REPLICAS=$(yq '.kubernetes.deployment.replicas // 1' "$CONFIG_FILE")
CONTAINER_PORT=$(yq '.kubernetes.deployment.port' "$CONFIG_FILE")
SERVICE_PORT=$(yq '.kubernetes.deployment.service_port // 80' "$CONFIG_FILE")

# Parse INGRESS_HOSTS properly
if command -v mapfile >/dev/null 2>&1; then
  mapfile -t INGRESS_HOSTS < <(yq '.ingress.hosts[]' "$CONFIG_FILE")
else
  INGRESS_HOSTS=()
  while IFS= read -r host; do
    INGRESS_HOSTS+=("$host")
  done < <(yq '.ingress.hosts[]' "$CONFIG_FILE")
fi

CERT_EMAIL=$(yq '.ingress.tls.email' "$CONFIG_FILE")
ENABLE_TLS=$(yq '.ingress.tls.enabled // true' "$CONFIG_FILE")

echo "✅ Config parsed:"
echo "   Project: $PROJECT_NAME"
echo "   Hosts: $(printf '%s, ' "${INGRESS_HOSTS[@]}" | sed 's/, $//')"

# Test SSH connection and Pulumi
echo "🔧 Testing server connection..."
sshpass -p "EnfyraTest1105@" ssh -o ConnectTimeout=10 root@31.97.114.147 << TESTEOF
set -e
echo "✅ Connected to server"

cd /deployments/enfyra-backend || exit 1

# Clear any stuck operations
echo "🧹 Clearing stuck operations..."
pulumi cancel --force --yes || true

# Quick status check
echo "📋 Current stack status:"
pulumi stack ls || echo "No stacks"

echo "🔍 Current pods:"
microk8s kubectl get pods || echo "No pods"

echo "✅ Test completed"
TESTEOF

echo "🎉 Quick test finished!"