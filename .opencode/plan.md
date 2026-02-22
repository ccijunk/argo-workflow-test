# Plan: Deploy Argo Workflows with MinIO

## Objective
Deploy Argo Workflows with MinIO (S3-compatible storage) in the same Helm release, then test `argo cp` functionality.

## Steps

### 1. Start Minikube
```bash
minikube start -p test-cluster
```

### 2. Add Helm Repositories
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add minio https://helm.min.io/
helm repo update
```

### 3. Create Helm Chart with MinIO Integration
Create parent chart with dependencies:
- `Chart.yaml` - Parent chart with MinIO as dependency
- `values.yaml` - Configuration for Argo + MinIO

### 4. Install Argo Workflows with MinIO
```bash
helm install argo ./ -n argo --create-namespace
```

### 5. Verify Installation
```bash
kubectl rollout status deployment/argo-workflows-workflow-controller -n argo
kubectl get pods -n argo
```

### 6. Test Argo CP
- Install Argo CLI
- Create test workflow with artifact output to MinIO
- Run `argo cp` to copy artifact


### 7. Test on exit to delete 
- Test secret workflow: apply secret → echo in workflow → auto-delete via onExit
- adjust rbac make workflow 
- write a test script, kubectl apply secret and the argo submit
- add test case to ./test-case-workflow and check

## Configuration Details

### MinIO (values.yaml)
- rootUser: minioadmin
- rootPassword: minioadmin
- bucket: argo-artifacts
- service: NodePort for easy access

### Argo Workflows (values.yaml)
- Artifact repository configured to use MinIO
- S3 endpoint: minio:9000
- Insecure: true (for local testing)
- Credentials via Kubernetes secret
