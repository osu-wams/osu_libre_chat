# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] - 2026-02-13

### Added

#### Infrastructure
- **Dockerfile**: Multi-stage Docker build for LibreChat based on Node.js 20 Alpine
  - Clones LibreChat v0.7.6 from official repository
  - Builds frontend and backend
  - Includes health check endpoint
  - Optimized for production deployment

- **Bicep Templates** (`infra/bicep/main.bicep`):
  - Azure Container Apps environment with integrated Log Analytics
  - Cosmos DB for MongoDB (serverless mode for cost optimization)
  - Azure Cache for Redis (Basic C0 tier)
  - Azure Blob Storage for file uploads
  - Auto-scaling configuration (1-5 replicas)
  - Secure secret management
  - TLS encryption for all connections
  - Multi-container support (LibreChat + Meilisearch)

- **Deployment Automation**:
  - `infra/deploy.sh`: Bash script for automated Azure deployment
  - `infra/bicep/parameters.dev.json`: Development environment parameters
  - `infra/bicep/parameters.prod.json`: Production environment parameters
  - Environment variable validation
  - Automated resource group creation
  - Deployment status reporting

- **CI/CD Pipeline** (`.github/workflows/deploy.yml`):
  - Bicep template validation
  - Container image build and push to ACR
  - Automated deployment to Azure
  - Support for multiple environments (dev, prod)
  - Manual workflow dispatch option
  - Secure GITHUB_TOKEN permissions

#### Configuration
- **librechat.yaml**: LibreChat application configuration
  - File upload settings
  - Interface customization
  - Endpoint configuration template
  - Azure Storage integration

- **.env.template**: Environment variables template
  - All required configuration options documented
  - Secure defaults
  - AI provider configuration examples

#### Documentation
- **README.md**: Comprehensive overview
  - Architecture diagram
  - Quick start guide
  - Configuration instructions
  - Cost optimization tips
  - Monitoring and troubleshooting

- **ARCHITECTURE.md**: Technical architecture documentation
  - Component descriptions
  - Network architecture
  - Security implementation
  - Scaling strategy
  - Cost estimation
  - Best practices

- **DEPLOYMENT_GUIDE.md**: Step-by-step deployment instructions
  - Prerequisites
  - Three deployment options (quick, manual, CI/CD)
  - Post-deployment configuration
  - AI provider setup
  - Monitoring setup
  - Troubleshooting guide

- **QUICK_REFERENCE.md**: Command reference
  - Common Azure CLI commands
  - Configuration file index
  - Resource list
  - Cost estimates
  - Security checklist

#### Development Files
- **.gitignore**: Standard ignore patterns for Node.js, Azure, and temporary files
- **.dockerignore**: Optimized Docker build exclusions

### Features

#### Security
- All secrets stored in Container App secrets (not environment variables)
- HTTPS enforced for external traffic
- TLS 1.2+ for MongoDB and Redis connections
- Private blob storage (no public access)
- Secure container registry authentication
- Explicit GitHub Actions permissions
- Zero security vulnerabilities (CodeQL verified)

#### Scalability
- Auto-scaling based on HTTP concurrent requests
- Support for 1-5 replicas (configurable)
- Serverless Cosmos DB for variable workloads
- Redis caching for performance
- Container Apps built-in load balancing

#### Monitoring
- Integrated Log Analytics workspace
- Application and container logs
- Performance metrics
- Health check endpoints
- 30-day log retention

#### Cost Optimization
- Cosmos DB serverless mode (pay-per-request)
- Redis Basic C0 (smallest tier)
- Standard LRS storage
- Container Apps dynamic scaling
- Estimated cost: $47-116/month for dev environment

### Technical Details

#### Technologies Used
- **Infrastructure**: Azure Bicep
- **Container Orchestration**: Azure Container Apps
- **Database**: Azure Cosmos DB (MongoDB API v4.2)
- **Cache**: Azure Cache for Redis
- **Storage**: Azure Blob Storage
- **Monitoring**: Azure Log Analytics
- **CI/CD**: GitHub Actions
- **Container Runtime**: Docker
- **Application**: LibreChat v0.7.6

#### Resources Deployed
1. Log Analytics Workspace (logs and monitoring)
2. Container Apps Environment (hosting platform)
3. Cosmos DB Account (MongoDB-compatible database)
4. Cosmos DB Database (LibreChat database)
5. Redis Cache (session management)
6. Storage Account (file uploads)
7. Blob Service (storage service)
8. Blob Container (uploads container)
9. Container App (LibreChat + Meilisearch)

#### Supported Scenarios
- Development and production environments
- Custom container registry integration
- External MongoDB support
- Multiple Azure regions
- Custom domain support
- Azure AD authentication (configuration required)

### References
- Based on recommendations from: https://www.elumenotion.com/journal/librechatbicep/
- LibreChat: https://github.com/danny-avila/LibreChat
- Azure Container Apps: https://learn.microsoft.com/azure/container-apps/

### Security Summary
✅ All security scans passed (CodeQL)
✅ No vulnerabilities detected
✅ GitHub Actions permissions properly scoped
✅ Secrets management implemented correctly
✅ TLS encryption enforced everywhere
✅ Network security properly configured

### Known Limitations
- Bicep template shows one warning about conditional Cosmos DB resource (non-critical)
- Deployment requires active Azure subscription
- Testing requires manual verification with Azure credentials
- Custom domain setup requires additional Azure resources (not automated)

### Future Enhancements
- Azure API Management integration
- Azure Front Door for global distribution
- Azure Key Vault integration
- Custom domain automation
- Azure AD B2C for enterprise auth
- Multi-region deployment templates
- Automated backup configuration
- Cost management alerts
