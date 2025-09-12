#!/usr/bin/env bash
# One-shot setup for Pulumi AKS stack (Python).
# - Creates venv and installs requirements.txt
# - Ensures az login
# - Creates/selects Pulumi stack
# - Applies config from .env.dev (or CLI overrides)
# - Optionally pins Kubernetes version (leave empty to let Azure choose)
#
# Usage:
#   chmod +x setup-config.sh
#   ./setup-config.sh [-s dev] [--region "East US"] [--kv-name my-uniq-kv] [--acr-name myuniqacr12345] [--aks-name my-aks]
#
# You may also edit .env.dev and just run:
#   ./setup-config.sh

set -euo pipefail

STACK="dev"
PROJECT="aks-foundation"
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="venv"
REQ_FILE="requirements.txt"
ENV_FILE=".env.dev"

# -------- helpers --------
log() { printf "\033[1;34m[setup]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; }

# -------- parse args (very light) --------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--stack) STACK="$2"; shift 2 ;;
    --region) AZ_REGION="$2"; shift 2 ;;
    --rg-name) RG_NAME="$2"; shift 2 ;;
    --aks-name) AKS_NAME="$2"; shift 2 ;;
    --acr-name) ACR_NAME="$2"; shift 2 ;;
    --kv-name) KV_NAME="$2"; shift 2 ;;
    --grafana-name) GRAFANA_NAME="$2"; shift 2 ;;
    --dns-prefix) DNS_PREFIX="$2"; shift 2 ;;
    --node-size) NODE_SIZE="$2"; shift 2 ;;
    --node-count) NODE_COUNT="$2"; shift 2 ;;
    --node-rg) NODE_RG="$2"; shift 2 ;;
    --k8s-version) K8S_VERSION="$2"; shift 2 ;; # optional; omit to let Azure pick
    --tenant-id) TENANT_ID="$2"; shift 2 ;;
    --sub-id) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --department) DEPARTMENT="$2"; shift 2 ;;
    *) err "Unknown arg: $1"; exit 1 ;;
  esac
done

# -------- load .env.dev if present --------
if [[ -f "$ENV_FILE" ]]; then
  log "Loading $ENV_FILE"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  warn "$ENV_FILE not found; using CLI args or defaults."
fi

# defaults if not set by env or CLI
AZ_REGION="${AZ_REGION:-East US}"
RG_NAME="${RG_NAME:-pulumi-rg}"
AKS_NAME="${AKS_NAME:-pulami-aks-dev}"
ACR_NAME="${ACR_NAME:-pulamiacr12345}"     # must be globally unique (a–z0–9)
KV_NAME="${KV_NAME:-pulumi-kv-dev-01}"     # must be globally unique (a–z0–9-), 3–24 chars
GRAFANA_NAME="${GRAFANA_NAME:-pulumi-grafana}"  # <= 23 chars
DNS_PREFIX="${DNS_PREFIX:-az-pulumi-cluster}"
NODE_SIZE="${NODE_SIZE:-Standard_D2s_v3}"  # pick a supported size for eastus
NODE_COUNT="${NODE_COUNT:-1}"
NODE_RG="${NODE_RG:-mc-resource-group-pulumi}"
DEPARTMENT="${DEPARTMENT:-delivery}"
OWNER="${OWNER:-example@kyndryl.com}"
TENANT_ID="${TENANT_ID:-8196ddea-f6c5-4044-8209-53ad1fdaebbf}"     # <- update if needed
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-05276564-4a5f-40d6-b156-3ed5768e3bf3}" # <- update if needed
# K8S_VERSION optional; leave empty to let Azure pick

# -------- sanity checks --------
if (( ${#GRAFANA_NAME} > 23 )); then
  err "grafanaName must be <= 23 chars (got ${#GRAFANA_NAME})"; exit 1
fi

if ! command -v az >/dev/null 2>&1; then
  err "Azure CLI (az) not found. Install: https://aka.ms/azure-cli"; exit 1
fi
if ! command -v pulumi >/dev/null 2>&1; then
  err "Pulumi CLI not found. Install: https://www.pulumi.com/docs/install/"; exit 1
fi

# -------- ensure az login --------
if ! az account show >/dev/null 2>&1; then
  log "Logging into Azure..."
  az login >/dev/null
fi
log "Setting subscription: $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"

# -------- venv + deps --------
if [[ ! -d "$VENV_DIR" ]]; then
  log "Creating venv at $VENV_DIR"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
python --version

if [[ -f "$REQ_FILE" ]]; then
  log "Installing Python deps from $REQ_FILE"
  pip install --upgrade pip
  pip install -r "$REQ_FILE"
else
  warn "No requirements.txt found; skipping pip install."
fi

# -------- pulumi stack + config --------
log "Selecting/creating stack: $STACK"
pulumi stack select "$STACK" || pulumi stack init "$STACK"

# Provider-wide Azure config (helps auth), namespaced under 'azure'
pulumi config set azure:tenantId "$TENANT_ID" -s "$STACK"
pulumi config set azure:subscriptionId "$SUBSCRIPTION_ID" -s "$STACK"

# Project config (namespaced under project name)
NS="$PROJECT"

pulumi config set "$NS:location"             "$AZ_REGION"   -s "$STACK"
pulumi config set "$NS:resourceGroupName"    "$RG_NAME"     -s "$STACK"
pulumi config set "$NS:aksClusterName"       "$AKS_NAME"    -s "$STACK"
pulumi config set "$NS:dnsPrefix"            "$DNS_PREFIX"  -s "$STACK"
pulumi config set "$NS:nodeVmSize"           "$NODE_SIZE"   -s "$STACK"
pulumi config set "$NS:nodeCount"            "$NODE_COUNT"  -s "$STACK"
pulumi config set "$NS:nodeResourceGroup"    "$NODE_RG"     -s "$STACK"
pulumi config set "$NS:tenantId"             "$TENANT_ID"   -s "$STACK"
pulumi config set "$NS:subscriptionId"       "$SUBSCRIPTION_ID" -s "$STACK"
pulumi config set "$NS:department"           "$DEPARTMENT"  -s "$STACK"
pulumi config set "$NS:owner"                "$OWNER"       -s "$STACK"
pulumi config set "$NS:grafanaName"          "$GRAFANA_NAME" -s "$STACK"
pulumi config set "$NS:keyVaultName"         "$KV_NAME"     -s "$STACK"
pulumi config set "$NS:acrName"              "$ACR_NAME"    -s "$STACK"

# defaultTags as a JSON map
pulumi config set "$NS:defaultTags"          '{"env":"dev","owner":"you@example.com"}' -s "$STACK"

# Optional: pin k8s version (if provided); otherwise Azure picks
if [[ -n "${K8S_VERSION:-}" ]]; then
  pulumi config set "$NS:kubernetesVersion" "$K8S_VERSION" -s "$STACK"
else
  pulumi config rm "$NS:kubernetesVersion" -s "$STACK" >/dev/null 2>&1 || true
fi

log "Done. You can now run: pulumi up"
