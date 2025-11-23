#!/bin/bash
# GpuBudget GCP Auto-Setup - Runs automatically when Cloud Shell opens

set -e

echo "========================================="
echo "🚀 GpuBudget GCP Auto-Setup Starting..."
echo "========================================="

# Extract TOKEN_ID from current URL or environment
# Cloud Shell doesn't pass URL params as env vars, so we need to get it from the user
if [ -z "$TOKEN_ID" ]; then
    # Try to get from Cloud Shell metadata or URL
    # For now, prompt user to paste the full URL
    echo "⚠️  Could not detect TOKEN_ID automatically"
    echo ""
    echo "Please open this URL in your browser to get your token:"
    echo "https://app.gpubudget.com/connect/gcp"
    echo ""
    read -p "Paste the full Cloud Shell URL here: " FULL_URL

    # Extract TOKEN_ID from URL
    TOKEN_ID=$(echo "$FULL_URL" | grep -oP 'TOKEN_ID=\K[^&]+' || echo "")
fi

if [ -z "$TOKEN_ID" ]; then
    echo "❌ ERROR: Could not find TOKEN_ID"
    echo "Please ensure you're using the magic link from GpuBudget"
    exit 1
fi

# Fetch actual token from backend
echo "🔑 Fetching authentication token..."
BACKEND_RESPONSE=$(curl -s "https://api.gpubudget.com/cloud-accounts/token/$TOKEN_ID")

if echo "$BACKEND_RESPONSE" | grep -q "token"; then
    export AUTH_TOKEN=$(echo "$BACKEND_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['token'])")
    export BACKEND_URL=$(echo "$BACKEND_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('backend_url', 'https://api.gpubudget.com'))")

    echo "✓ Authentication successful"
    echo ""

    # Make script executable and run
    chmod +x gcp-cloudshell.sh

    echo "🚀 Running automatic GCP setup..."
    ./gcp-cloudshell.sh --auto-run
else
    echo "❌ ERROR: Failed to retrieve token"
    echo "Response: $BACKEND_RESPONSE"
    exit 1
fi
