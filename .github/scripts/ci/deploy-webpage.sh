#!/bin/bash
set -e

echo "Deploying Webpage: Copying Helm index..."
mkdir -p webpage/public
cp index.yaml webpage/public/index.yaml

echo "Deploying Webpage: Building Astro site..."
cd webpage
npm run build
