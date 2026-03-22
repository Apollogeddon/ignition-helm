#!/bin/bash
set -e

echo "Updating Helm dependencies for all charts..."
for dir in charts/*; do
  if [ -d "$dir" ] && [ -f "$dir/Chart.yaml" ]; then
    # Only update if the chart actually has dependencies defined or an existing lock file
    if grep -q "dependencies:" "$dir/Chart.yaml" || [ -f "$dir/Chart.lock" ]; then
      echo "Updating dependencies for $dir..."
      helm dependency update "$dir"
    else
      echo "Skipping $dir (no dependencies found)."
    fi
  fi
done
