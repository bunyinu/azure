#!/bin/bash
# Azure Setup Wrapper - Handles token fetch and execution

set -e

echo "========================================="
echo "🔑 GpuBudget Azure Setup"
echo "========================================="
echo ""

# Function to extract TOKEN_ID from current directory or URL
get_token_id() {
    # Check if .token_id file exists (created by URL redirect)
    if [ -f ".token_id" ]; then
        cat .token_id
        return
    fi

    # Prompt user for TOKEN_ID from URL
    echo "Please copy the TOKEN_ID from your browser URL"
    echo "(It's the part after #TOKEN_ID= in the Cloud Shell URL)"
    echo ""
    read -p "TOKEN_ID: " user_token
    echo "$user_token"
}

TOKEN_ID=$(get_token_id)

if [ -z "$TOKEN_ID" ]; then
    echo "❌ No TOKEN_ID provided"
    echo ""
    echo "Please:"
    echo "  1. Go to https://app.gpubudget.com/connect/azure"
    echo "  2. Click 'Connect Azure'"
    echo "  3. Copy the TOKEN_ID from the Cloud Shell URL"
    echo "  4. Run this script again"
    exit 1
fi

# Fetch token from backend
echo "🔑 Fetching authentication token..."
BACKEND_RESPONSE=$(curl -s "https://api.gpubudget.com/cloud-accounts/token/$TOKEN_ID")

if echo "$BACKEND_RESPONSE" | grep -q '"token"'; then
    export AUTH_TOKEN=$(echo "$BACKEND_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['token'])" 2>/dev/null)
    export BACKEND_URL=$(echo "$BACKEND_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('backend_url', 'https://api.gpubudget.com'))" 2>/dev/null)

    if [ -n "$AUTH_TOKEN" ]; then
        echo "✅ Authentication successful!"
        echo "🚀 Starting Azure deployment..."
        echo ""

        chmod +x azure-cloudshell.sh
        ./azure-cloudshell.sh --auto-run true
    else
        echo "❌ Failed to parse authentication token"
        exit 1
    fi
else
    echo "❌ Failed to retrieve token"
    echo "Response: $BACKEND_RESPONSE"
    echo ""
    echo "Please check:"
    echo "  - TOKEN_ID is correct"
    echo "  - Token hasn't expired (valid for 1 hour)"
    echo "  - You're connected to the internet"
    exit 1
fi
