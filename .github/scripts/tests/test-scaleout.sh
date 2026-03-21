#!/bin/bash
set -e

echo "Starting Scaleout Architecture Deployment Test..."

# Install with NetworkPolicy, HPA and redundancy enabled
echo "Installing ignition-scaleout..."
helm install scaleout charts/scaleout \
  --set frontend.networkPolicy.enabled=true \
  --set backend.networkPolicy.enabled=true \
  --set frontend.hpa.enabled=true \
  --set frontend.hpa.minReplicas=2 \
  --set backend.hpa.enabled=true \
  --set backend.hpa.minReplicas=1
  
echo "Waiting for StatefulSets rollout..."
kubectl rollout status statefulset/ignition-scaleout-backend --timeout=10m
kubectl rollout status statefulset/ignition-scaleout-frontend --timeout=10m

# 1. Sanity check: StatusPing via exec (localhost)
echo "Verifying StatusPing (localhost on frontend)..."
kubectl exec ignition-scaleout-frontend-0 -- curl -s -f http://localhost:8088/StatusPing

# 2. Test Network Policy (should deny from different namespace)
echo "Testing NetworkPolicy (cross-namespace denial)..."
kubectl create namespace test-ns-scaleout || true

# Test Frontend blocking
echo "Checking if traffic to Frontend from other namespace is blocked..."
if kubectl run test-pod-fr --namespace test-ns-scaleout --image=curlimages/curl --restart=Never --rm -i -- \
  curl -s -m 5 http://ignition-scaleout-frontend.default.svc.cluster.local:8088/StatusPing; then
  echo "ERROR: NetworkPolicy FAILED - Traffic to Frontend was allowed"
  exit 1
else
  echo "SUCCESS: NetworkPolicy blocked unauthorized traffic to Frontend."
fi

# Test Backend blocking
echo "Checking if traffic to Backend from other namespace is blocked..."
if kubectl run test-pod-bk --namespace test-ns-scaleout --image=curlimages/curl --restart=Never --rm -i -- \
  curl -s -m 5 http://ignition-scaleout-backend.default.svc.cluster.local:8088/StatusPing; then
  echo "ERROR: NetworkPolicy FAILED - Traffic to Backend was allowed"
  exit 1
else
  echo "SUCCESS: NetworkPolicy blocked unauthorized traffic to Backend."
fi

# 3. Verify internal connectivity (Frontend to Backend)
echo "Verifying internal connectivity (Frontend can reach Backend)..."
if kubectl exec ignition-scaleout-frontend-0 -- curl -s -f -m 5 http://ignition-scaleout-backend:8088/StatusPing; then
  echo "SUCCESS: Internal connectivity verified."
else
  echo "ERROR: Internal connectivity FAILED - Frontend cannot reach Backend"
  exit 1
fi

# 4. Verify HPA & PDB
echo "Verifying HPA resources..."
# Frontend HPA
echo "Checking Frontend HPA..."
if kubectl get hpa ignition-scaleout-frontend; then
  MIN_REPS=$(kubectl get hpa ignition-scaleout-frontend -o jsonpath='{.spec.minReplicas}')
  if [ "$MIN_REPS" != "2" ]; then
    echo "ERROR: Frontend HPA minReplicas mismatch (expected 2, got $MIN_REPS)"
    exit 1
  fi
  echo "SUCCESS: Frontend HPA verified."
else
  echo "ERROR: Frontend HPA resource not found"
  exit 1
fi

# Backend HPA
echo "Checking Backend HPA..."
if kubectl get hpa ignition-scaleout-backend; then
  echo "SUCCESS: Backend HPA found."
else
  echo "ERROR: Backend HPA resource not found"
  exit 1
fi

# PDBs (should be created because HPA is enabled)
echo "Checking PDB resources..."
if kubectl get pdb ignition-scaleout-frontend && kubectl get pdb ignition-scaleout-backend; then
  echo "SUCCESS: PDB resources found for both components."
else
  echo "ERROR: One or more PDB resources missing"
  exit 1
fi

echo "Cleaning up scaleout deployment..."
helm uninstall scaleout
echo "Scaleout Deployment Test PASSED."
