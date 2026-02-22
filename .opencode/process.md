# Argo Workflows with MinIO - Process Summary

## Date: 2026-02-21

## Objective
Deploy Argo Workflows with MinIO (S3-compatible storage) in the same Helm release, then test `argo cp` functionality.

## Steps Completed

### 1. Start Minikube Cluster
- Started minikube with docker driver
- Required proxy configuration for image pulls
- Used proxy `192.168.10.205:7897` (Clash Verge with "Allow LAN" enabled)
- Proxy worked when host proxy env vars were unset before starting minikube

```bash
minikube start -p test-cluster --kubernetes-version=1.32.0 --driver=docker --container-runtime=containerd --cni=bridge --docker-env=HTTP_PROXY=http://192.168.10.205:7897 --docker-env=HTTPS_PROXY=http://192.168.10.205:7897
```

### 2. Add Helm Repositories
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### 3. File Structure Created
- `./helm/` - Helm chart directory
  - `Chart.yaml` - Parent chart with dependencies
  - `values.yaml` - Configuration values
- `./test-case-workflow/` - Test workflow directory
  - `test-workflow.yaml` - Sample workflow with artifacts

### 4. Chart Configuration Updates

#### Chart.yaml
- Argo Workflows chart: `0.47.3` (v3.7.9)
- MinIO chart: `17.0.21` (latest)
- appVersion: `3.7.9`

#### values.yaml Key Settings
- `global.security.allowInsecureImages: true` - Allow custom MinIO image
- `argo-workflows.artifactRepository.s3` - MinIO configuration
- `argo-workflows.workflow.serviceAccount` - RBAC service account
- `argo-workflows.workflow.rbac.create: true` - Enable RBAC

### 5. Issues Encountered & Solutions

#### Issue 1: MinIO Image Not Found
- **Problem**: `bitnami/minio:2025.7.23-debian-12-r3` not found
- **Solution**: Use `minio/minio:RELEASE.2025-09-07T16-13-09Z` with `global.security.allowInsecureImages: true`

#### Issue 2: MinIO Permission Error
- **Problem**: `file access denied` on `/data` directory
- **Solution**: Added `volumePermissions.enabled: true` and mounted to `/bitnami/minio/data`

#### Issue 3: RBAC ServiceAccount Not Created
- **Problem**: `workflow.serviceAccount.create: true` didn't create the SA in the release namespace
- **Manual Fix**: Created SA manually with `kubectl create serviceaccount argo-workflow -n argo`
- **Note**: Chart version 0.47.3 creates SA in different namespace than release

#### Issue 4: DNS Resolution Failed
- **Problem**: Workflow pods couldn't resolve `minio` service
- **Root Cause**: MinIO service name is `argo-minio` not `minio`
- **Solution**: Changed endpoint from `minio:9000` to `argo-minio:9000`

#### Issue 5: Bucket Does Not Exist
- **Problem**: MinIO bucket `argo-artifacts` doesn't exist
- **Status**: Pending - need to create bucket

### 6. Current Status
- Argo Workflows controller: Running
- Argo Workflows server: Running
- MinIO: Running
- Test workflow: Submitted but failed (bucket issue)

### 7. Pending Tasks
- Create MinIO bucket (need to implement)

### 8. MinIO Bucket Creation
- Created job using minio/mc:latest to create bucket
- Bucket `argo-artifacts` successfully created

### 9. Artifact Upload Test
- Created workflow `artifact-upload-` with artifacts
- Workflow succeeded, artifacts stored in MinIO at `test/<workflow-name>/`

### 10. Argo CP Test
- Required server auth mode: `server.authModes: [server]`
- Must provide explicit token: `ARGO_SERVER=localhost:2746 ARGO_SECURE=false ARGO_TOKEN="<token>" argo cp ...`
- Adding `client` mode (`[server, client]`) allows CLI to use kubeconfig credentials without explicit token
- Port-forward to argo-server required
- Artifacts successfully copied to local directory

### 11. Archive Configuration
- Use `archive: none: {}` in workflow artifacts to prevent compression
- Without this, artifacts are gzipped by default

## Commands Used

### Install/Upgrade
```bash
cd helm && helm install argo . -n argo --create-namespace \
  --set global.security.allowInsecureImages=true \
  --set workflow.authModes[0]=client \
  --set workflow.serviceAccount.create=true \
  --set workflow.serviceAccount.name=argo-workflow \
  --set workflow.rbac.create=true
```

### Submit Test Workflow
```bash
argo submit test-case-workflow/test-workflow.yaml -n argo --serviceaccount argo-workflow
```

## Proxy Configuration Notes
- Host proxy: `127.0.0.1:7897` (Clash Verge)
- Must enable "Allow LAN" in Clash Verge to bind to `0.0.0.0:7897`
- Host network IP: `192.168.10.205`
- Minikube needs proxy via `--docker-env` flags
- Must unset host proxy env vars before starting minikube to avoid conflict

## Final Working Configuration

### values.yaml Key Settings
```yaml
global:
  security:
    allowInsecureImages: true

argo-workflows:
  server:
    serviceType: NodePort
    authModes:
      - server  # Minimum required for argo cp; add "client" for kubeconfig fallback
  artifactRepository:
    s3:
      bucket: argo-artifacts
      endpoint: argo-minio:9000
      insecure: true
      accessKeySecret:
        name: argo-minio
        key: root-user
      secretKeySecret:
        name: argo-minio
        key: root-password
  workflow:
    serviceAccount:
      create: true
      name: argo-workflow

minio:
  image:
    registry: docker.io
    repository: minio/minio
    tag: RELEASE.2025-09-07T16-13-09Z
  volumePermissions:
    enabled: true
```

### Complete argo cp Command
```bash
# 1. Create server token
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

# 2. Get token
TOKEN=$(kubectl get secret server-token -n argo -o jsonpath='{.data.token}' | base64 -d)

# 3. Start port-forward (separate terminal)
kubectl port-forward -n argo svc/argo-argo-workflows-server 2746:2746

# 4. Copy artifacts
ARGO_SERVER=localhost:2746 ARGO_SECURE=false ARGO_TOKEN="$TOKEN" \
  argo cp <workflow-name> <output-dir> -n argo
```

### Test Workflow (test-case-workflow/upload-test.yaml)
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: artifact-upload-
spec:
  entrypoint: main
  templates:
  - name: main
    container:
      image: alpine:latest
      command: [sh, -c]
      args:
        - |
          echo "Hello from Argo Workflows" > /tmp/output.txt
          echo "Test artifact content" > /tmp/test.txt
      name: main
    outputs:
      artifacts:
      - name: output
        path: /tmp/output.txt
        archive:
          none: {}
        s3:
          bucket: argo-artifacts
          key: test/{{ workflow.name }}/output.txt
      - name: test
        path: /tmp/test.txt
        archive:
          none: {}
        s3:
          bucket: argo-artifacts
          key: test/{{ workflow.name }}/test.txt
```

## Summary
- Argo Workflows v3.7.9 deployed with MinIO
- Artifacts successfully uploaded to MinIO bucket
- `argo cp` tested and working
- Quickstart guide created at `.opencode/quickstart.md`
