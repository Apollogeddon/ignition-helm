#!/bin/bash
set -e

echo "Updating Helm dependencies for all charts..."
for dir in charts/*; do
  if [ -d "$dir" ]; then
    if [ -f "$dir/Chart.yaml" ]; then
      echo "Updating dependencies for $dir..."
      helm dependency update "$dir"
    fi
  fi
done
