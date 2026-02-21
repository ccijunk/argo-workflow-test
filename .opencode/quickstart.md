# Quickstart: Argo Workflows with MinIO and argo cp

This guide walks you through deploying Argo Workflows with MinIO and testing the `argo cp` command.

## Prerequisites

- minikube
- helm
- kubectl
- argo CLI

## Steps

### 1. Start Minikube

```bash
# Start minikube with proxy configuration (adjust proxy IP/port as needed)
minikube start -p test-cluster \
  --kubernetes-version=1.32.0 \
  --driver=docker \
  --container-runtime=containerd \
  --cni=bridge \
  --docker-env=HTTP_PROXY=http://192.168.10.205:7897 \
  --docker-env=HTTPS_PROXY=http://192.168.10.205:7897
```

### 2. Add Helm Repositories

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### 3. Install Argo Workflows with MinIO

```bash
# From the repo root
cd helm
helm install argo-workflow . -n argo --create-namespace
```

Wait for all pods to be ready:

```bash
kubectl get pods -n argo -w
```

### 4. Wait for MinIO Bucket

The bucket `argo-artifacts` is automatically created by the Helm chart. Verify:

```bash
kubectl exec -n argo deploy/argo-minio -- mc ls local/
```

If bucket doesn't exist, create manually:
```bash
kubectl exec -n argo deploy/argo-minio -- mc mb local/argo-artifacts
```

### 5. Create Service Account Token for argo cp

The argo CLI needs a token to authenticate with the server:

```bash
# Create a service account for the server if not exists
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: server-token
  namespace: argo
  annotations:
    kubernetes.io/service-account.name: argo-argo-workflows-server
type: kubernetes.io/service-account-token
EOF

# Wait for secret to be created
sleep 3

# Get the token
TOKEN=$(kubectl get secret server-token -n argo -o jsonpath='{.data.token}' | base64 -d)
```

### 6. Submit Test Workflow

```bash
argo submit test-case-workflow/upload-test.yaml \
  -n argo \
  --serviceaccount argo-workflow
```

Wait for the workflow to succeed:

```bash
argo list -n argo
```

### 7. Start Port Forward

In a separate terminal, start port-forward to the Argo server:

```bash
kubectl port-forward -n argo svc/argo-argo-workflows-server 2746:2746
```

### 8. Copy Artifacts with argo cp

```bash
# Get the latest workflow name
WORKFLOW=$(argo list -n argo --no-headers | head -1 | awk '{print $1}')

# Copy artifacts
ARGO_SERVER=localhost:2746 \
ARGO_SECURE=false \
ARGO_TOKEN="$TOKEN" \
  argo cp "$WORKFLOW" ./artifacts -n argo
```

### 9. Verify Artifacts

```bash
find ./artifacts -type f -name "*.txt" -exec cat {} \;
```

Expected output:
```
Hello from Argo Workflows
Test artifact content
```

## Troubleshooting

### Token not valid error

Ensure server auth mode is enabled in values.yaml:
```yaml
server:
  authModes:
    - server
```

Then upgrade the release:
```bash
helm upgrade argo ./ -n argo
```

**Note**: Adding `client` mode as well (`[server, client]`) allows the CLI to use kubeconfig credentials without explicitly passing a token. With only `server` mode, you must always provide the token explicitly.

### Cannot connect to server

Ensure port-forward is running:
```bash
kubectl port-forward -n argo svc/argo-argo-workflows-server 2746:2746
```

### Bucket does not exist

Create the bucket manually:
```bash
kubectl exec -n argo argo-minio-0 -- mc mb local/argo-artifacts
# Or if using deployment:
kubectl exec -n argo deploy/argo-minio -- mc mb local/argo-artifacts
```
