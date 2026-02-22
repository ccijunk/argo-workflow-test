#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-case-workflow"
NAMESPACE="${NAMESPACE:-argo}"

echo "=== Step 1: Apply Secret ==="
kubectl apply -f "$SCRIPT_DIR/secret.yaml" -n "$NAMESPACE"
echo "Secret created"

echo ""
echo "=== Step 2: Verify Secret Exists ==="
kubectl get secret test-onexit-secret -n "$NAMESPACE"
echo ""

echo "=== Step 3: Submit Workflow ==="
WORKFLOW_NAME=$(argo submit "$SCRIPT_DIR/delete-secret-on-exit.yaml" -n "$NAMESPACE" -o name | cut -d'/' -f2)
echo "Submitted workflow: $WORKFLOW_NAME"

echo ""
echo "=== Step 4: Wait for Workflow Completion ==="
argo wait "$WORKFLOW_NAME" -n "$NAMESPACE"
argo get "$WORKFLOW_NAME" -n "$NAMESPACE"
argo logs "$WORKFLOW_NAME" -n "$NAMESPACE"

echo ""
echo "=== Step 5: Verify Secret Deleted ==="
if kubectl get secret test-onexit-secret -n "$NAMESPACE" 2>/dev/null; then
  echo "FAIL: Secret still exists"
  exit 1
else
  echo "SUCCESS: Secret was deleted by onExit handler"
fi
