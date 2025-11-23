#!/usr/bin/env bash
# One-click Azure onboarding for GpuBudget via Cloud Shell.
# - Creates a resource group if needed
# - Deploys the ARM template with managed identity
# - Captures outputs and POSTs to the backend

set -euo pipefail

BACKEND_URL="${BACKEND_URL:-https://api.gpubudget.com}"
ALLOW_CONTROL="${ALLOW_CONTROL:-false}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
LOCATION="${LOCATION:-eastus}"
AUTH_TOKEN="${AUTH_TOKEN:-}"
AUTO_RUN="${AUTO_RUN:-false}"

usage() {
  cat <<EOF
Usage: ./azure-cloudshell.sh [--resource-group NAME] [--location LOCATION] [--allow-control true|false] [--auth-token TOKEN]
Env vars:
  BACKEND_URL       Backend base URL (default: https://api.gpubudget.com)
  ALLOW_CONTROL     true to grant VM control; false for read-only (default: false)
  RESOURCE_GROUP    Azure resource group name (will be created if not exists)
  LOCATION          Azure region (default: eastus)
  AUTH_TOKEN        GpuBudget authentication token (required for backend submission)
  AUTO_RUN          true to skip prompts (default: false)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    --location)
      LOCATION="$2"
      shift 2
      ;;
    --allow-control)
      ALLOW_CONTROL="$2"
      shift 2
      ;;
    --auth-token)
      AUTH_TOKEN="$2"
      shift 2
      ;;
    --auto-run)
      AUTO_RUN="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing $1; install it first." >&2; exit 1; }
}

require az
require jq

# Ensure logged in
echo "Checking Azure login status..."
if ! az account show >/dev/null 2>&1; then
  echo "Please log in to Azure:"
  az login
fi

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Using subscription: $SUBSCRIPTION_ID"
echo "Tenant ID: $TENANT_ID"

# Determine resource group
if [[ -z "$RESOURCE_GROUP" ]]; then
  if [[ "$AUTO_RUN" == "true" ]]; then
    RESOURCE_GROUP="gpubudget-connector-rg"
    echo "Auto-run mode: using resource group '$RESOURCE_GROUP'"
  else
    echo "Available resource groups:"
    az group list --query "[].name" -o tsv | nl
    read -r -p "Enter resource group name (or press Enter to create 'gpubudget-connector-rg'): " INPUT_RG
    if [[ -z "$INPUT_RG" ]]; then
      RESOURCE_GROUP="gpubudget-connector-rg"
    else
      RESOURCE_GROUP="$INPUT_RG"
    fi
  fi
fi

# Create resource group if it doesn't exist
if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Creating resource group '$RESOURCE_GROUP' in location '$LOCATION'..."
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null
else
  echo "Using existing resource group '$RESOURCE_GROUP'"
fi

# Deploy ARM template
echo "Deploying GpuBudget connector (Managed Identity + Reader role)..."
DEPLOYMENT_NAME="gpubudget-$(date +%Y%m%d-%H%M%S)"
TEMPLATE_FILE="$(dirname "$0")/infra/azure-connector.json"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Error: ARM template not found at $TEMPLATE_FILE" >&2
  exit 1
fi

DEPLOYMENT_OUTPUT=$(az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DEPLOYMENT_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --parameters allowControl="$ALLOW_CONTROL" \
  --query 'properties.outputs' \
  -o json)

echo "Deployment completed successfully!"

# Extract outputs
MANAGED_IDENTITY_CLIENT_ID=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.managedIdentityClientId.value')
MANAGED_IDENTITY_RESOURCE_ID=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.managedIdentityResourceId.value')
OUTPUT_TENANT_ID=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.tenantId.value')
OUTPUT_SUBSCRIPTION_ID=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.subscriptionId.value')

echo ""
echo "Deployment outputs:"
echo "  Managed Identity Client ID: $MANAGED_IDENTITY_CLIENT_ID"
echo "  Tenant ID: $OUTPUT_TENANT_ID"
echo "  Subscription ID: $OUTPUT_SUBSCRIPTION_ID"
echo ""

# Prompt for auth token if not provided
if [[ -z "$AUTH_TOKEN" ]]; then
  echo "To register this Azure account with GpuBudget, you need an authentication token."
  echo "Get your token by logging in at ${BACKEND_URL%/api.*}/login"
  echo ""
  read -r -p "Enter your GpuBudget auth token (or press Enter to skip): " AUTH_TOKEN
  if [[ -z "$AUTH_TOKEN" ]]; then
    echo ""
    echo "Skipping backend registration."
    echo "To manually register, POST this data to $BACKEND_URL/cloud-accounts/azure:"
    jq -n \
      --arg tenant_id "$OUTPUT_TENANT_ID" \
      --arg subscription_id "$OUTPUT_SUBSCRIPTION_ID" \
      --arg client_id "$MANAGED_IDENTITY_CLIENT_ID" \
      --argjson allow_control "$( [[ "$ALLOW_CONTROL" == "true" ]] && echo true || echo false )" \
      '{
        tenant_id: $tenant_id,
        subscription_id: $subscription_id,
        client_id: $client_id,
        allow_control: $allow_control
      }'
    exit 0
  fi
fi

# POST to backend
echo "Registering Azure account with GpuBudget backend..."
PAYLOAD=$(jq -n \
  --arg tenant_id "$OUTPUT_TENANT_ID" \
  --arg subscription_id "$OUTPUT_SUBSCRIPTION_ID" \
  --arg client_id "$MANAGED_IDENTITY_CLIENT_ID" \
  --argjson allow_control "$( [[ "$ALLOW_CONTROL" == "true" ]] && echo true || echo false )" \
  '{
    tenant_id: $tenant_id,
    subscription_id: $subscription_id,
    client_id: $client_id,
    allow_control: $allow_control
  }')

HTTP_STATUS=$(curl -s -o /tmp/gpubudget-azure-onboard.log -w "%{http_code}" \
  -X POST "$BACKEND_URL/cloud-accounts/azure" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -d "$PAYLOAD")

if [[ "$HTTP_STATUS" -ge 200 && "$HTTP_STATUS" -lt 300 ]]; then
  echo "Success! Azure account registered with GpuBudget."
else
  echo "Backend responded with status $HTTP_STATUS. See /tmp/gpubudget-azure-onboard.log for details." >&2
  cat /tmp/gpubudget-azure-onboard.log
  exit 1
fi

echo ""
echo "Azure onboarding complete!"
