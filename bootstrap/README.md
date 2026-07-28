# Node Bootstrap

These scripts are used to rebuild a Raspberry Pi CM4 node running DietPi and rejoin it to the k3s cluster.

## Requirements

- Fresh DietPi installation
- SSH enabled
- Network connectivity to the cluster
- Git installed (or install it first)

## Worker Recovery

Clone the repository:

```bash
git clone git@github.com:TT3D/k3s-homelab.git
cd k3s-homelab
```

Set the required environment variables:

```bash
export K3S_SERVER_URL=https://10.39.10.101:6443
export K3S_TOKEN=<your-node-token>
```

Run the bootstrap script:

```bash
sudo ./bootstrap/bootstrap-node.sh cube02 worker
```

Verify the node joined the cluster:

```bash
kubectl get nodes
```

## Notes

- Do not commit the real K3S token to Git.
- Application data is stored on the NFS server.
- Kubernetes workloads are restored automatically by Argo CD.
