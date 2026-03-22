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
minikube start -p test-cluster \
  --kubernetes-version=1.32.0 \
  --driver=docker \
  --container-runtime=containerd \
  --cni=bridge
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
helm install argo-workflows . -n argo --create-namespace
```

Wait for all pods to be ready:

```bash
kubectl get pods -n argo -w
```

### 4. Wait for MinIO Bucket

The bucket `argo-artifacts` is automatically created by the Helm chart. Verify:

```bash
kubectl exec -n argo deploy/argo-workflows-minio -- mc ls local/
```

If bucket doesn't exist, create manually:
```bash
kubectl exec -n argo deploy/argo-workflows-minio -- mc mb local/argo-artifacts
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
    kubernetes.io/service-account.name: argo-workflows-server
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
kubectl port-forward -n argo svc/argo-workflows-server 2746:2746 > /tmp/pf.log 2>&1 &
```

### 8. Copy Artifacts with argo cp

```bash
# Get the latest workflow name
WORKFLOW=$(argo list -n argo --no-headers | head -1 | awk '{print $1}')
# Copy artifacts
ARGO_SERVER=localhost:2746 \
ARGO_SECURE=false \
ARGO_TOKEN="$TOKEN" \
  argo cp "$WORKFLOW" ./artifacts -n argo --path {artifactName}
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
helm upgrade argo-workflows  ./ -n argo
```

**Note**: Adding `client` mode as well (`[server, client]`) allows the CLI to use kubeconfig credentials without explicitly passing a token. With only `server` mode, you must always provide the token explicitly.

### Cannot connect to server

Ensure port-forward is running:
```bash
kubectl port-forward -n argo svc/argo-workflows-server 2746:2746
```

### Bucket does not exist

Create the bucket manually:
```bash
kubectl exec -n argo argo-minio-0 -- mc mb local/argo-artifacts
# Or if using deployment:
kubectl exec -n argo deploy/argo-minio -- mc mb local/argo-artifacts
```

## Test: onExit Handler to Delete Secret

This test demonstrates:
1. Injecting secret as environment variables into a workflow
2. Using `onExit` handler to delete the secret after workflow completion

### 1. RBAC Configuration

The Helm chart already includes RBAC rules to allow the workflow service account to delete secrets. Check `helm/values.yaml`:

```yaml
workflow:
  rbac:
    create: true
    rules:
      - apiGroups: [""]
        resources: ["secrets"]
        verbs: ["delete"]
```

If upgrading from an older release, ensure RBAC is applied:
```bash
helm upgrade argo-workflows ./helm -n argo
```

### 2. Create Secret

```bash
kubectl apply -f test-case-workflow/secret.yaml -n argo
```

### 3. Run Test Script

```bash
./test-on-exit-secret.sh
```

Or manually:

```bash
# Verify secret exists
kubectl get secret test-onexit-secret -n argo

# Submit workflow
argo submit test-case-workflow/delete-secret-on-exit.yaml -n argo --serviceaccount argo-workflow

# Wait for completion
argo wait delete-secret-on-exit-xxx -n argo

# Verify secret is deleted
kubectl get secret test-onexit-secret -n argo  # Should fail
```

Expected output:
```
=== Step 1: Apply Secret ===
secret/test-onexit-secret created

=== Step 2: Verify Secret Exists ===
NAME                 TYPE     DATA   AGE
test-onexit-secret   Opaque   2      0s

=== Step 3: Submit Workflow ===
Submitted workflow: delete-secret-on-exit-xxx

=== Step 4: Wait for Workflow Completion ===
delete-secret-on-exit-xxx Succeeded

=== Step 5: Verify Secret Deleted ===
SUCCESS: Secret was deleted by onExit handler
```

### How It Works

**Workflow definition** (`test-case-workflow/delete-secret-on-exit.yaml`):

- **Main template**: Reads secret via environment variables and echoes the values
- **onExit template**: Runs `kubectl delete secret` to clean up the secret

```yaml
spec:
  onExit: exit-handler
  templates:
  - name: main
    container:
      env:
        - name: SECRET_USERNAME
          valueFrom:
            secretKeyRef:
              name: test-onexit-secret
              key: username
  - name: exit-handler
    container:
      args:
        - kubectl delete secret test-onexit-secret -n argo
```
