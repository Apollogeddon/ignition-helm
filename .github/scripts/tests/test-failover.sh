#!/bin/bash
set -e

echo "Starting Failover Architecture Deployment Test..."

# Install with NetworkPolicy enabled
echo "Installing ignition-failover..."
helm install failover charts/failover --set ignition.networkPolicy.enabled=true

# Wait for rollout
echo "Waiting for StatefulSet rollout..."
kubectl rollout status statefulset/ignition-failover --timeout=10m

# 1. Sanity check: StatusPing via exec (localhost)
echo "Verifying StatusPing (localhost)..."
kubectl exec ignition-failover-0 -- curl -s -f http://localhost:8088/StatusPing

# 2. Test Persistence
echo "Testing Persistence..."
echo "Writing persistence test file..."
kubectl exec ignition-failover-0 -- sh -c "echo 'persistence-works' > /usr/local/bin/ignition/data/persistence-test.txt"

echo "Restarting pod ignition-failover-0..."
kubectl delete pod ignition-failover-0
kubectl rollout status statefulset/ignition-failover --timeout=5m

echo "Verifying file content after restart..."
kubectl exec ignition-failover-0 -- cat /usr/local/bin/ignition/data/persistence-test.txt | grep "persistence-works"

# 3. Test Network Policy (should deny from different namespace)
echo "Testing NetworkPolicy (cross-namespace denial)..."
kubectl create namespace test-ns-failover || true

# This should fail (timeout or connection refused)
echo "Checking if traffic from other namespace is blocked..."
if kubectl run test-pod-failover --namespace test-ns-failover --image=curlimages/curl --restart=Never --rm -i -- \
  curl -s -m 5 http://ignition-failover.default.svc.cluster.local:8088/StatusPing; then
  echo "ERROR: NetworkPolicy FAILED - Traffic from other namespace was allowed"
  exit 1
else
  echo "SUCCESS: NetworkPolicy blocked unauthorized traffic."
fi

echo "Cleaning up failover deployment..."
helm uninstall failover
echo "Failover Deployment Test PASSED."
