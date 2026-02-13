#!/bin/bash

# LibreChat Azure Deployment Script
# This script deploys LibreChat to Azure using Bicep templates

set -e

# Configuration
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-librechat-rg}"
LOCATION="${LOCATION:-eastus}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    log_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Set subscription if provided
if [ -n "$SUBSCRIPTION_ID" ]; then
    log_info "Setting subscription to $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Get current subscription
CURRENT_SUBSCRIPTION=$(az account show --query id -o tsv)
log_info "Using subscription: $CURRENT_SUBSCRIPTION"

# Create resource group if it doesn't exist
log_info "Checking resource group: $RESOURCE_GROUP_NAME"
if ! az group show --name "$RESOURCE_GROUP_NAME" &> /dev/null; then
    log_info "Creating resource group: $RESOURCE_GROUP_NAME in $LOCATION"
    az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION"
else
    log_info "Resource group already exists"
fi

# Deploy Bicep template
log_info "Deploying LibreChat infrastructure..."
DEPLOYMENT_NAME="librechat-deployment-$(date +%Y%m%d-%H%M%S)"

# Check if parameter file exists
PARAM_FILE="infra/bicep/parameters.${ENVIRONMENT}.json"
if [ ! -f "$PARAM_FILE" ]; then
    log_warn "Parameter file $PARAM_FILE not found, using default parameters"
    PARAM_ARG=""
else
    PARAM_ARG="--parameters $PARAM_FILE"
fi

# Deploy
az deployment group create \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file infra/bicep/main.bicep \
    $PARAM_ARG \
    --parameters location="$LOCATION" environmentName="$ENVIRONMENT"

# Get deployment outputs
log_info "Deployment completed successfully!"
log_info "Retrieving deployment outputs..."

LIBRECHAT_URL=$(az deployment group show \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query properties.outputs.librechatUrl.value \
    -o tsv)

CONTAINER_APP_NAME=$(az deployment group show \
    --name "$DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query properties.outputs.containerAppName.value \
    -o tsv)

# Display results
echo ""
log_info "==================================="
log_info "Deployment Summary"
log_info "==================================="
log_info "Resource Group: $RESOURCE_GROUP_NAME"
log_info "Environment: $ENVIRONMENT"
log_info "Container App: $CONTAINER_APP_NAME"
log_info "LibreChat URL: https://$LIBRECHAT_URL"
log_info "==================================="
echo ""
log_info "You can access LibreChat at: https://$LIBRECHAT_URL"
log_info "To view logs, run: az containerapp logs show -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP_NAME --follow"
