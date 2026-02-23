#!/usr/bin/env bash
# k3d cluster for the todo-app: create or delete.
# Usage: ./cluster.sh create | delete

set -e
CLUSTER_NAME="${K3D_CLUSTER_NAME:-todo-cluster}"

case "${1:-}" in
  create)
    if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME} "; then
      echo "Cluster ${CLUSTER_NAME} already exists. Use: k3d cluster start ${CLUSTER_NAME}"
      exit 0
    fi
    echo "Creating k3d cluster: ${CLUSTER_NAME}"
    k3d cluster create "$CLUSTER_NAME" \
      --agents 1 \
      --port "3000:3000@loadbalancer" \
      --wait
    echo "Done. Use: kubectl config use-context k3d-${CLUSTER_NAME}"
    ;;
  delete)
    echo "Deleting k3d cluster: ${CLUSTER_NAME}"
    k3d cluster delete "$CLUSTER_NAME" || true
    echo "Done."
    ;;
  *)
    echo "Usage: $0 create | delete"
    exit 1
    ;;
esac
