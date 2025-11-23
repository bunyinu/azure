#!/usr/bin/env bash
# One-click GCP onboarding for GpuBudget via Cloud Shell.
# - Lists projects with GPUs detected.
# - Creates a service account with minimal read-only roles (Compute Viewer + Billing Viewer).
# - Adds control roles only if ALLOW_CONTROL=true.
# - Generates a key and POSTs it to the backend.

set -euo pipefail

BACKEND_URL="${BACKEND_URL:-https://api.gpubudget.com}"
ALLOW_CONTROL="${ALLOW_CONTROL:-false}"
SA_NAME="${SA_NAME:-gpubudget-connector}"
TMP_KEY="$(mktemp)"
PROJECT_IDS="${PROJECT_IDS:-}"
AUTO_RUN="${AUTO_RUN:-false}"

usage() {
  cat <<EOF
Usage: ./gcp-cloudshell.sh [--projects proj1,proj2] [--allow-control true|false] [--auto-run true|false]
Env vars:
  BACKEND_URL       Backend base URL (default: https://api.gpubudget.com)
  ALLOW_CONTROL     true to grant control roles; false for read-only (default: false)
  PROJECT_IDS       Comma-separated project IDs to onboard; if empty, you will be prompted
  AUTO_RUN          true to skip prompt and auto-select GPU projects (or first project)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --projects|--project-ids)
      PROJECT_IDS="$2"
      shift 2
      ;;
    --allow-control)
      ALLOW_CONTROL="$2"
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

require gcloud
require jq

echo "Fetching projects..."
PROJECTS=($(gcloud projects list --format="value(projectId)"))
if [[ ${#PROJECTS[@]} -eq 0 ]]; then
  echo "No projects accessible with your account." >&2
  exit 1
fi

declare -a GPU_PROJECTS=()
for p in "${PROJECTS[@]}"; do
  if gcloud compute instances list --project "$p" --filter="guestAccelerators:*" --limit=1 --format="value(name)" 2>/dev/null | grep -q .; then
    GPU_PROJECTS+=("$p")
  fi
done

echo "Projects with GPUs detected:"
if [[ ${#GPU_PROJECTS[@]} -eq 0 ]]; then
  echo "  (none detected; you can still proceed)"
else
  for gp in "${GPU_PROJECTS[@]}"; do echo "  - $gp"; done
fi

SELECTED=()
if [[ -n "$PROJECT_IDS" ]]; then
  IFS=',' read -r -a SELECTED <<< "$PROJECT_IDS"
elif [[ "$AUTO_RUN" == "true" ]]; then
  if [[ ${#GPU_PROJECTS[@]} -gt 0 ]]; then
    SELECTED=("${GPU_PROJECTS[@]}")
    echo "Auto-running for GPU projects: ${SELECTED[*]}"
  else
    SELECTED=("${PROJECTS[0]}")
    echo "Auto-running for first project: ${SELECTED[*]}"
  fi
else
  echo "Select project(s) to onboard (comma-separated index or ID). Available projects:"
  idx=1
  for p in "${PROJECTS[@]}"; do
    mark=""
    for gp in "${GPU_PROJECTS[@]}"; do
      if [[ "$p" == "$gp" ]]; then mark="(GPU)"; fi
    done
    echo "  [$idx] $p $mark"
    ((idx++))
  done
  read -r -p "Enter project IDs or indexes (comma-separated): " ANSWER
  if [[ -z "$ANSWER" ]]; then
    echo "Project selection required." >&2
    exit 1
  fi
  IFS=',' read -r -a INPUTS <<< "$ANSWER"
  for val in "${INPUTS[@]}"; do
    val=$(echo "$val" | xargs)
    if [[ "$val" =~ ^[0-9]+$ ]]; then
      idx=$((val-1))
      if [[ $idx -ge 0 && $idx -lt ${#PROJECTS[@]} ]]; then
        SELECTED+=("${PROJECTS[$idx]}")
      fi
    else
      SELECTED+=("$val")
    fi
  done
fi

if [[ ${#SELECTED[@]} -eq 0 ]]; then
  echo "No projects selected." >&2
  exit 1
fi

for PROJECT_ID in "${SELECTED[@]}"; do
  echo "---- Onboarding project: $PROJECT_ID ----"
  echo "Enabling required APIs in $PROJECT_ID..."
  gcloud services enable compute.googleapis.com cloudbilling.googleapis.com --project "$PROJECT_ID" >/dev/null

  SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo "Service account $SA_EMAIL exists; reusing."
  else
    gcloud iam service-accounts create "$SA_NAME" --project "$PROJECT_ID" --display-name "GpuBudget Connector" >/dev/null
  fi

  echo "Granting read-only roles..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/compute.viewer" >/dev/null
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/billing.viewer" >/dev/null

  if [[ "$ALLOW_CONTROL" == "true" ]]; then
    echo "Granting control roles (compute.instanceAdmin.v1, storageAdmin)..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:$SA_EMAIL" \
      --role="roles/compute.instanceAdmin.v1" >/dev/null
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:$SA_EMAIL" \
      --role="roles/storage.admin" >/dev/null
  fi

  echo "Creating service account key..."
  gcloud iam service-accounts keys create "$TMP_KEY" --iam-account "$SA_EMAIL" --project "$PROJECT_ID" >/dev/null

  PAYLOAD=$(jq -c --arg project_id "$PROJECT_ID" --argjson allow_control "$( [[ "$ALLOW_CONTROL" == "true" ]] && echo true || echo false )" \
    --arg sa_json "$(cat "$TMP_KEY" | jq -c .)" \
    '{
      project_id: $project_id,
      allow_control: $allow_control,
      service_account_info: ($sa_json | fromjson)
    }')

  echo "Posting credentials to backend at $BACKEND_URL/cloud-accounts/gcp ..."
  HTTP_STATUS=$(curl -s -o /tmp/gpubudget-onboard.log -w "%{http_code}" \
    -X POST "$BACKEND_URL/cloud-accounts/gcp" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  if [[ "$HTTP_STATUS" -ge 200 && "$HTTP_STATUS" -lt 300 ]]; then
    echo "Success! Account onboarded for project $PROJECT_ID."
  else
    echo "Backend responded with status $HTTP_STATUS. See /tmp/gpubudget-onboard.log for details." >&2
  fi
done

rm -f "$TMP_KEY"
