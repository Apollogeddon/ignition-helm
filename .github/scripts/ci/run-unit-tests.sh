#!/bin/bash
set -e

echo "Running unit tests for all charts..."
for dir in charts/*; do
  if [ -d "$dir/tests" ]; then
    echo "Running unit tests for $dir"
    helm unittest "$dir"
  fi
done
