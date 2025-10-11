#!/usr/bin/env bash
set -euo pipefail

# generate-config.sh
# Generate a MetalLB ConfigMap using node InternalIPs as the address pool.
# Usage:
#   ./generate-config.sh               # use all nodes
#   ./generate-config.sh "node-role.kubernetes.io/worker=true"  # use nodes matching selector
# Output: emits a ConfigMap YAML to stdout. Redirect to a file and apply with kubectl.

SELECTOR="${1:-}"
SEL_ARGS=()
if [ -n "$SELECTOR" ]; then
  SEL_ARGS=("-l" "$SELECTOR")
fi

# Collect node internal IPs. Use kubectl -o json and parse with Python for robustness.
if [ ${#SEL_ARGS[@]} -gt 0 ]; then
  NODE_JSON=$(kubectl get nodes "${SEL_ARGS[@]}" -o json)
else
  NODE_JSON=$(kubectl get nodes -o json)
fi
mapfile -t LINES < <(python3 - <<PY
import sys, json
j = json.load(sys.stdin)
out = []
for item in j.get('items', []):
    name = item.get('metadata', {}).get('name', '')
    ips = []
    for addr in item.get('status', {}).get('addresses', []):
        if addr.get('type') == 'InternalIP':
            ips.append(addr.get('address'))
    if ips:
        out.append(name + '|' + ';'.join(ips) + ';')
print('\n'.join(out))
PY
<<<"$NODE_JSON")

IPS=()
for line in "${LINES[@]}"; do
  # line format: <name>|<ip1>;<ip2>;...;
  ippart="${line#*|}"
  # take first IP listed (should be the InternalIP)
  ippart="${ippart%%;*}"
  ippart="${ippart## }"
  if [ -n "$ippart" ]; then
    IPS+=("$ippart")
  fi
done

if [ ${#IPS[@]} -eq 0 ]; then
  echo "Error: no node InternalIPs found. If you intended to select worker nodes, pass a label selector like 'node-role.kubernetes.io/worker=true'" >&2
  exit 1
fi

# Emit ConfigMap YAML
cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
EOF

for ip in "${IPS[@]}"; do
  printf "      - %s\n" "$ip"
done

# End
