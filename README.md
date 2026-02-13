# LibreChat on Azure Container Apps

This repository contains the infrastructure code and deployment scripts for deploying LibreChat on Azure using Container Apps and Bicep orchestration.

## Overview

LibreChat is a free, open-source AI chat platform that allows you to integrate with multiple AI providers (OpenAI, Azure OpenAI, Anthropic, Google, etc.) through a single, unified interface.

This deployment uses:
- **Azure Container Apps** for hosting the LibreChat application
- **Azure Cosmos DB for MongoDB** for data persistence
- **Azure Cache for Redis** for session management and caching
- **Azure Blob Storage** for file uploads
- **Bicep** for Infrastructure as Code

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Container Apps                     │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │   LibreChat      │         │  Meilisearch     │         │
│  │   Container      │◄────────┤  Container       │         │
│  └────────┬─────────┘         └──────────────────┘         │
│           │                                                  │
└───────────┼──────────────────────────────────────────────────┘
            │
            ├──────────► Azure Cosmos DB (MongoDB API)
            │
            ├──────────► Azure Cache for Redis
            │
            └──────────► Azure Blob Storage
```

## Prerequisites

- Azure subscription
- Azure CLI installed and configured
- Docker (optional, for building custom images)
- Bicep CLI (included with Azure CLI)

## Quick Start

### 1. Login to Azure

```bash
az login
az account set --subscription <your-subscription-id>
```

### 2. Deploy the Infrastructure

```bash
# Set environment variables
export RESOURCE_GROUP_NAME="librechat-rg"
export LOCATION="eastus"
export ENVIRONMENT="dev"

# Run the deployment script
./infra/deploy.sh
```

### 3. Access LibreChat

After deployment, the script will output the URL for your LibreChat instance:

```
LibreChat URL: https://librechat-dev-xxxxx.azurecontainerapps.io
```

## Configuration

### Environment-Specific Deployments

The infrastructure supports multiple environments (dev, staging, prod). Parameter files are located in `infra/bicep/`:

- `parameters.dev.json` - Development environment
- `parameters.prod.json` - Production environment

### Customizing the Deployment

Edit the parameter files to customize:

- **Location**: Azure region for deployment
- **Container Image**: Custom container registry and image tag
- **MongoDB**: Use external MongoDB instead of Cosmos DB
- **Resource Sizing**: Adjust CPU, memory, and scaling rules

### AI Provider Configuration

After deployment, you'll need to configure AI providers:

1. Access your Container App environment variables:
   ```bash
   az containerapp show -n <container-app-name> -g <resource-group> --query properties.template.containers[0].env
   ```

2. Add API keys for your chosen providers:
   - OpenAI: `OPENAI_API_KEY`
   - Azure OpenAI: `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT`
   - Anthropic: `ANTHROPIC_API_KEY`
   - Google: `GOOGLE_KEY`

3. Update the container app:
   ```bash
   az containerapp update -n <container-app-name> -g <resource-group> \
     --set-env-vars "OPENAI_API_KEY=sk-..." "ANTHROPIC_API_KEY=sk-..."
   ```

Alternatively, edit `librechat.yaml` and redeploy.

## Building Custom Container Image

If you want to build a custom container image:

```bash
# Build the image
docker build -t librechat:latest .

# Tag for your Azure Container Registry
docker tag librechat:latest <your-acr>.azurecr.io/librechat:latest

# Push to ACR
az acr login --name <your-acr>
docker push <your-acr>.azurecr.io/librechat:latest

# Update deployment parameters to use your custom image
# Edit infra/bicep/parameters.dev.json and set:
# - containerRegistryServer: "<your-acr>.azurecr.io"
# - containerRegistryUsername: "<your-acr>"
# - containerImageTag: "latest"
```

## Cost Optimization

The default deployment uses cost-optimized Azure services:

- **Cosmos DB**: Serverless mode (pay-per-request)
- **Redis**: Basic tier, smallest size (C0)
- **Container Apps**: Dynamic scaling from 1-5 replicas
- **Storage**: Standard LRS

For production deployments, consider:
- Using provisioned throughput for Cosmos DB if you have predictable load
- Upgrading Redis to Standard tier for better performance
- Adjusting auto-scaling rules based on your traffic patterns

## Monitoring and Troubleshooting

### View Container Logs

```bash
az containerapp logs show \
  -n <container-app-name> \
  -g <resource-group> \
  --follow
```

### View Metrics

```bash
az monitor metrics list \
  --resource <container-app-resource-id> \
  --metric-names "Requests,CpuUsage,MemoryUsage"
```

### Common Issues

1. **Container fails to start**: Check environment variables and secrets are correctly configured
2. **Database connection errors**: Verify Cosmos DB is running and connection string is correct
3. **File upload failures**: Check Azure Storage account permissions

## Security Considerations

- All secrets are stored in Container App secrets (not in environment variables)
- HTTPS is enforced for all external traffic
- MongoDB and Redis connections use TLS
- Storage account has public access disabled
- Container registry credentials are stored securely

## Updating LibreChat

To update to a newer version of LibreChat:

```bash
# Update the Dockerfile with new version
# Build and push new image
# Redeploy using the deployment script

./infra/deploy.sh
```

Or use Container Apps revisions for zero-downtime updates:

```bash
az containerapp revision copy \
  -n <container-app-name> \
  -g <resource-group> \
  --image <your-acr>.azurecr.io/librechat:new-version
```

## Clean Up

To remove all deployed resources:

```bash
az group delete --name <resource-group> --yes --no-wait
```

## Additional Resources

- [LibreChat Documentation](https://www.librechat.ai/docs)
- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

## Support

For LibreChat-specific issues, visit the [LibreChat GitHub repository](https://github.com/danny-avila/LibreChat).

For Azure deployment issues, open an issue in this repository.

## License

This infrastructure code is provided under The Unlicense. LibreChat itself is licensed under the MIT License.