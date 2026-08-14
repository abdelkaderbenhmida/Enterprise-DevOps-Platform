#!/usr/bin/env bash
set -euo pipefail

# Refresh kubeadm join tokens and print join commands for control planes and workers
# Run on a control-plane node (e.g., vm08-k8s-cp1)

echo "=== Kubernetes Join Token Refresh ==="
echo ""

# Create new token for worker nodes (TTL 24h)
WORKER_TOKEN=$(kubeadm token create --print-join-command --ttl 24h0m0s)
echo "Worker node join command (valid 24h):"
echo "$WORKER_TOKEN"
echo ""

# Create new token for control plane nodes (TTL 24h)
CP_TOKEN=$(kubeadm token create --print-join-command --ttl 24h0m0s)
CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
echo "Control plane join command (valid 24h):"
echo "$CP_TOKEN --certificate-key $CERT_KEY"
echo ""

# List existing tokens
echo "Current tokens:"
kubeadm token list
echo ""

# Save to file for Ansible to fetch
cat > /tmp/k8s-join-tokens.json <<EOF
{
  "worker_join_command": "$WORKER_TOKEN",
  "cp_join_command": "$CP_TOKEN",
  "certificate_key": "$CERT_KEY",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "Tokens saved to /tmp/k8s-join-tokens.json"