metal-lb — quick install and config using node IPs

What I added
- `metallb-config-template.yaml` — a template ConfigMap for MetalLB. Edit the addresses or use the generator below.
- `generate-config.sh` — small script that queries cluster nodes and emits a MetalLB ConfigMap using each node's InternalIP as an address entry. Usage examples are below.

Notes and warnings
- MetalLB hands out IPs from the address pool. If you use actual node IPs as load-balancer IPs, ensure those IPs are not in active use by other services on the network or they will conflict. It’s common to reserve a separate range in the same L2 network for MetalLB.
- The script selects node InternalIP values. To limit to worker nodes, pass a label selector like `node-role.kubernetes.io/worker=true`.

Quick steps
1) Install MetalLB (apply official manifests):

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/main/config/manifests/metallb-native.yaml
```

2) Generate a ConfigMap using all nodes:

```bash
cd metal-lb
chmod +x generate-config.sh
./generate-config.sh > metallb-config.yaml
kubectl apply -f metallb-config.yaml
```

3) Or generate using only worker nodes (if your workers have the label `node-role.kubernetes.io/worker=true`):

```bash
./generate-config.sh "node-role.kubernetes.io/worker=true" > metallb-config.yaml
kubectl apply -f metallb-config.yaml
```

4) Or edit `metallb-config-template.yaml` and apply it directly if you prefer manual ranges.

Verify

```bash
kubectl -n metallb-system get pods
kubectl -n metallb-system get configmap config -o yaml
# Create a test LoadBalancer service to confirm allocation
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: metallb-test
  namespace: default
spec:
  selector:
    app: some-nonexistent-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: LoadBalancer
EOF
kubectl get svc metallb-test -o wide
```

Cleanup test

```bash
kubectl delete svc metallb-test
kubectl delete -f metallb-config.yaml
kubectl delete -f https://raw.githubusercontent.com/metallb/metallb/main/config/manifests/metallb-native.yaml
```

If you want me to: (reply with a number)
1) Run the install and generate/apply the config now (I will run commands one-by-one and report any errors).
2) Just leave the files as-is (already created). 
3) Modify the generator to produce a CIDR range instead of single IPs (helpful if you want a contiguous range).


