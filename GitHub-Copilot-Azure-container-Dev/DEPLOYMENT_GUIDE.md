# Deployment Guide for LibreChat on Azure

This guide provides step-by-step instructions for deploying LibreChat to Azure Container Apps.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Deployment Options](#deployment-options)
4. [Post-Deployment Configuration](#post-deployment-configuration)
5. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools
- **Azure Subscription**: Active Azure subscription with Owner or Contributor role
- **Azure CLI**: Version 2.50 or later
  ```bash
  az --version
  ```
  Install: https://learn.microsoft.com/cli/azure/install-azure-cli

- **Docker** (Optional): For building custom container images
  ```bash
  docker --version
  ```

### Required Permissions
- Resource group creation
- Resource deployment
- Role assignment (for managed identities)

## Initial Setup

### 1. Clone the Repository

```bash
git clone https://github.com/osu-wams/osu_libre_chat.git
cd osu_libre_chat
```

### 2. Login to Azure

```bash
az login
```

### 3. Select Your Subscription

```bash
# List available subscriptions
az account list --output table

# Set active subscription
az account set --subscription "Your Subscription Name"
```

### 4. Configure Deployment Parameters

Edit the parameter file for your environment:

**For Development:**
```bash
nano infra/bicep/parameters.dev.json
```

**For Production:**
```bash
nano infra/bicep/parameters.prod.json
```

Key parameters to configure:
```json
{
  "location": "eastus",              // Azure region
  "environmentName": "dev",          // Environment name
  "appName": "librechat",            // Application prefix
  "containerImageTag": "latest"      // Container image version
}
```

## Deployment Options

### Option 1: Quick Deployment (Recommended)

Use the automated deployment script:

```bash
# Export configuration
export RESOURCE_GROUP_NAME="librechat-rg"
export LOCATION="eastus"
export ENVIRONMENT="dev"

# Make script executable
chmod +x infra/deploy.sh

# Run deployment
./infra/deploy.sh
```

The script will:
1. Create resource group
2. Deploy all Azure resources
3. Configure networking and security
4. Output the application URL

**Expected Output:**
```
[INFO] Deployment completed successfully!
[INFO] ===================================
[INFO] Deployment Summary
[INFO] ===================================
[INFO] Resource Group: librechat-rg
[INFO] Environment: dev
[INFO] Container App: librechat-dev-xxxxx-app
[INFO] LibreChat URL: https://librechat-dev-xxxxx.azurecontainerapps.io
[INFO] ===================================
```

### Option 2: Manual Deployment

If you prefer manual control:

#### Step 1: Create Resource Group
```bash
az group create \
  --name librechat-rg \
  --location eastus
```

#### Step 2: Validate Template
```bash
az deployment group validate \
  --resource-group librechat-rg \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/parameters.dev.json
```

#### Step 3: Deploy Template
```bash
az deployment group create \
  --name librechat-deployment \
  --resource-group librechat-rg \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/parameters.dev.json
```

#### Step 4: Get Outputs
```bash
az deployment group show \
  --name librechat-deployment \
  --resource-group librechat-rg \
  --query properties.outputs
```

### Option 3: GitHub Actions (CI/CD)

For automated deployments on code changes:

#### Step 1: Create Azure Service Principal
```bash
az ad sp create-for-rbac \
  --name "librechat-github-actions" \
  --role contributor \
  --scopes /subscriptions/{subscription-id}/resourceGroups/librechat-rg \
  --sdk-auth
```

#### Step 2: Add GitHub Secrets
Add the following secrets to your GitHub repository:
- `AZURE_CREDENTIALS`: Output from Step 1

#### Step 3: Configure GitHub Variables (Optional)
Add these variables if using custom container registry:
- `AZURE_CONTAINER_REGISTRY`: Your ACR name

#### Step 4: Push to Main Branch
```bash
git add .
git commit -m "Initial deployment configuration"
git push origin main
```

The workflow will automatically:
1. Validate Bicep templates
2. Build container image (if ACR configured)
3. Deploy to Azure
4. Output deployment URL

## Post-Deployment Configuration

### 1. Access the Application

Open the provided URL in your browser:
```
https://librechat-dev-xxxxx.azurecontainerapps.io
```

### 2. Configure AI Providers

#### Option A: Using Azure Portal
1. Go to Azure Portal
2. Navigate to your Container App
3. Go to "Containers" → "Environment variables"
4. Add your API keys:
   - `OPENAI_API_KEY`
   - `AZURE_OPENAI_API_KEY`
   - `ANTHROPIC_API_KEY`
5. Save and restart the container

#### Option B: Using Azure CLI
```bash
CONTAINER_APP_NAME="librechat-dev-xxxxx-app"
RESOURCE_GROUP="librechat-rg"

az containerapp update \
  -n $CONTAINER_APP_NAME \
  -g $RESOURCE_GROUP \
  --set-env-vars \
    "OPENAI_API_KEY=secretref:openai-key" \
  --secrets \
    "openai-key=sk-your-key-here"
```

#### Option C: Edit librechat.yaml
1. Update `librechat.yaml` with your configuration
2. Rebuild and redeploy the container

### 3. Create First User

Navigate to the URL and click "Sign Up" to create your first user account.

### 4. Configure User Registration

By default, registration is open. To restrict:

```bash
az containerapp update \
  -n $CONTAINER_APP_NAME \
  -g $RESOURCE_GROUP \
  --set-env-vars "ALLOW_REGISTRATION=false"
```

## Monitoring and Maintenance

### View Application Logs
```bash
az containerapp logs show \
  -n $CONTAINER_APP_NAME \
  -g $RESOURCE_GROUP \
  --follow
```

### View Metrics
```bash
az monitor metrics list \
  --resource <container-app-resource-id> \
  --metric "Requests"
```

### Update Application

To update to a new version:

1. **Using custom image:**
   ```bash
   # Build new image
   docker build -t librechat:v2 .
   docker tag librechat:v2 myregistry.azurecr.io/librechat:v2
   docker push myregistry.azurecr.io/librechat:v2
   
   # Update container app
   az containerapp update \
     -n $CONTAINER_APP_NAME \
     -g $RESOURCE_GROUP \
     --image myregistry.azurecr.io/librechat:v2
   ```

2. **Using deployment script:**
   ```bash
   ./infra/deploy.sh
   ```

### Scale the Application

```bash
# Manual scaling
az containerapp update \
  -n $CONTAINER_APP_NAME \
  -g $RESOURCE_GROUP \
  --min-replicas 2 \
  --max-replicas 10

# Auto-scaling (already configured)
az containerapp update \
  -n $CONTAINER_APP_NAME \
  -g $RESOURCE_GROUP \
  --scale-rule-name http-scaling \
  --scale-rule-type http \
  --scale-rule-http-concurrency 50
```

## Troubleshooting

### Container Fails to Start

**Symptom:** Container app shows "Failed" status

**Solution:**
1. Check logs:
   ```bash
   az containerapp logs show -n $CONTAINER_APP_NAME -g $RESOURCE_GROUP --tail 100
   ```

2. Verify environment variables are set correctly
3. Check that secrets are properly referenced

### Database Connection Errors

**Symptom:** "Failed to connect to MongoDB" in logs

**Solution:**
1. Verify Cosmos DB is running:
   ```bash
   az cosmosdb show -n <cosmos-name> -g $RESOURCE_GROUP
   ```

2. Check connection string format
3. Verify firewall rules allow Container Apps

### Redis Connection Errors

**Symptom:** "Redis connection failed" in logs

**Solution:**
1. Verify Redis is running:
   ```bash
   az redis show -n <redis-name> -g $RESOURCE_GROUP
   ```

2. Check that non-SSL port is disabled (should be)
3. Verify TLS is enabled

### File Upload Failures

**Symptom:** Cannot upload files in chat

**Solution:**
1. Verify storage account exists and is accessible
2. Check container exists (should be "uploads")
3. Verify connection string is correct:
   ```bash
   az storage account show-connection-string \
     -n <storage-name> \
     -g $RESOURCE_GROUP
   ```

### High Costs

**Symptom:** Azure bill higher than expected

**Solution:**
1. Review resource usage in Cost Management
2. Consider switching Cosmos DB from serverless to provisioned if usage is constant
3. Adjust Container Apps scaling limits
4. Enable auto-shutdown for non-production environments

## Advanced Configuration

### Custom Domain

```bash
# Add custom domain
az containerapp hostname add \
  -n $CONTAINER_APP_NAME \
  -g $RESOURCE_GROUP \
  --hostname chat.yourdomain.com

# Bind certificate
az containerapp hostname bind \
  -n $CONTAINER_APP_NAME \
  -g $RESOURCE_GROUP \
  --hostname chat.yourdomain.com \
  --certificate <certificate-id>
```

### Enable Azure AD Authentication

```bash
az containerapp auth update \
  -n $CONTAINER_APP_NAME \
  -g $RESOURCE_GROUP \
  --enabled true \
  --action RedirectToLoginPage \
  --aad-client-id <client-id> \
  --aad-client-secret <client-secret> \
  --aad-tenant-id <tenant-id>
```

### Multi-Region Deployment

For high availability, deploy to multiple regions:

1. Create resource groups in each region
2. Deploy using the same configuration
3. Use Azure Front Door or Traffic Manager for routing

## Support and Resources

- **LibreChat Docs**: https://www.librechat.ai/docs
- **Azure Container Apps**: https://learn.microsoft.com/azure/container-apps/
- **Azure Cosmos DB**: https://learn.microsoft.com/azure/cosmos-db/
- **Azure CLI Reference**: https://learn.microsoft.com/cli/azure/

## Clean Up

To delete all resources:

```bash
az group delete --name librechat-rg --yes --no-wait
```

**Warning:** This will delete all resources and data permanently!
