#!/usr/bin/env bash
# destroy.sh — Tear down the Pulumi AKS stack safely.
#
# Features:
#  - pulumi destroy (with confirmation)
#  - optional: purge soft-deleted Key Vault (requires --purge-kv)
#  - optional: delete Pulumi stack from backend (--remove-stack)
#  - optional: clean local artifacts (kubeconfig/venv) (--clean-local)
#
# Usage:
#   chmod +x destroy.sh
#   ./destroy.sh [-s dev] [--purge-kv] [--remove-stack] [--clean-local] [--yes]
#
# Environment:
#   Reads .env.dev if present (same vars as setup-config.sh).
#   You can also pass values via CLI flags.

set -euo pipefail

STACK="dev"
PROJECT="aks-foundation"
ENV_FILE=".env.dev"
ASSUME_YES="false"
PURGE_KV="false"
REMOVE_STACK="false"
CLEAN_LOCAL="false"

log()  { printf "\033[1;34m[destroy]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; }

# ------------- args -------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--stack) STACK="$2"; shift 2 ;;
    --purge-kv) PURGE_KV="true"; shift ;;
    --remove-stack) REMOVE_STACK="true"; shift ;;
    --clean-local) CLEAN_LOCAL="true"; shift ;;
    -y|--yes) ASSUME_YES="true"; shift ;;
    *) err "Unknown arg: $1"; exit 1 ;;
  esac
done

# ------------- prerequisites -------------
command -v pulumi >/dev/null 2>&1 || { err "Pulumi CLI not found"; exit 1; }
command -v az >/dev/null 2>&1      || { err "Azure CLI (az) not found"; exit 1; }

# ------------- load env (optional) -------------
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

# ------------- select stack -------------
log "Selecting stack: $STACK"
pulumi stack select "$STACK" >/dev/null

# ------------- discover config -------------
NS="$PROJECT"
# Try to read KV name from Pulumi config; ignore errors if unset
KV_NAME="$(pulumi config get "$NS:keyVaultName" -s "$STACK" 2>/dev/null || true)"
AZ_REGION="$(pulumi config get "$NS:location" -s "$STACK" 2>/dev/null || echo "East US")"
SUBSCRIPTION_ID="$(pulumi config get azure:subscriptionId -s "$STACK" 2>/dev/null || true)"

# Ensure az is pointing at the right subscription (if known)
if [[ -n "$SUBSCRIPTION_ID" ]]; then
  log "Setting Azure subscription: $SUBSCRIPTION_ID"
  az account set --subscription "$SUBSCRIPTION_ID"
fi

# ------------- confirm -------------
if [[ "$ASSUME_YES" != "true" ]]; then
  echo "About to destroy Pulumi stack '$STACK' in project '$PROJECT'."
  echo "Options: purge-kv=$PURGE_KV, remove-stack=$REMOVE_STACK, clean-local=$CLEAN_LOCAL"
  read -r -p "Proceed? [y/N] " REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]] || { warn "Aborted."; exit 0; }
fi

# ------------- destroy -------------
log "Running pulumi destroy for stack '$STACK'…"
if [[ "$ASSUME_YES" == "true" ]]; then
  pulumi destroy -y
else
  pulumi destroy
fi

# ------------- purge soft-deleted Key Vault (optional) -------------
if [[ "$PURGE_KV" == "true" ]]; then
  if [[ -z "$KV_NAME" ]]; then
    warn "keyVaultName not found in config; skipping purge."
  else
    log "Checking for soft-deleted Key Vault: $KV_NAME"
    # If the KV exists and is soft-deleted, purge it. Region must match where it was created.
    if az keyvault list-deleted --query "[?name=='$KV_NAME']" -o tsv | grep -q "$KV_NAME"; then
      log "Purging soft-deleted Key Vault '$KV_NAME' in region '$AZ_REGION'…"
      az keyvault purge --name "$KV_NAME" --location "$AZ_REGION"
    else
      log "No soft-deleted Key Vault named '$KV_NAME' found. Nothing to purge."
    fi
  fi
fi

# ------------- remove stack from backend (optional) -------------
if [[ "$REMOVE_STACK" == "true" ]]; then
  log "Removing Pulumi stack '$STACK' from backend…"
  if [[ "$ASSUME_YES" == "true" ]]; then
    pulumi stack rm "$STACK" --yes
  else
    pulumi stack rm "$STACK"
  fi
fi

# ------------- clean local artifacts (optional) -------------
if [[ "$CLEAN_LOCAL" == "true" ]]; then
  log "Cleaning local artifacts…"
  rm -f kubeconfig || true
  # Remove venv if it belongs to this repo
  if [[ -d "venv" ]]; then
    # Try to detect if venv is active and deactivate
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
      warn "A Python venv is active. Please 'deactivate' it before removing."
    fi
    rm -rf venv
  fi
fi

log "Done."
