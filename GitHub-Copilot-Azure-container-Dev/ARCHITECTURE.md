# LibreChat Azure Architecture

## Overview

This document describes the Azure architecture for deploying LibreChat using Container Apps and supporting services.

## Components

### 1. Azure Container Apps Environment

The Container Apps Environment provides the hosting platform for LibreChat and its dependencies.

**Features:**
- Integrated Log Analytics for monitoring
- Automatic HTTPS certificate management
- Built-in load balancing
- Auto-scaling capabilities

### 2. Application Containers

#### LibreChat Container
- **Image**: `ghcr.io/danny-avila/librechat:latest` (or custom)
- **Resources**: 1 vCPU, 2GB RAM
- **Port**: 3080
- **Scaling**: 1-5 replicas based on HTTP requests

#### Meilisearch Container
- **Image**: `getmeili/meilisearch:v1.5`
- **Resources**: 0.5 vCPU, 1GB RAM
- **Purpose**: Search functionality for conversations
- **Port**: 7700

### 3. Azure Cosmos DB for MongoDB

**Configuration:**
- **API**: MongoDB API (v4.2)
- **Mode**: Serverless (cost-effective for variable workloads)
- **Database**: LibreChat
- **Connection**: TLS encrypted

**Purpose:**
- User accounts and authentication
- Conversation history
- Settings and preferences
- Shared links and presets

### 4. Azure Cache for Redis

**Configuration:**
- **Tier**: Basic
- **Size**: C0 (250MB)
- **TLS**: Version 1.2
- **Policy**: allkeys-lru (evict oldest when full)

**Purpose:**
- Session management
- Rate limiting
- Caching frequently accessed data

### 5. Azure Blob Storage

**Configuration:**
- **Tier**: Standard LRS
- **Container**: uploads
- **Access**: Private (no public access)
- **TLS**: Version 1.2

**Purpose:**
- File uploads from conversations
- Image storage
- Document attachments

### 6. Log Analytics Workspace

**Configuration:**
- **Retention**: 30 days
- **Tier**: Pay-as-you-go

**Purpose:**
- Application logs
- Container logs
- Performance metrics
- Troubleshooting

## Network Architecture

```
Internet
   │
   ▼
Azure Front Door (HTTPS)
   │
   ▼
Container Apps Environment
   │
   ├──► LibreChat Container (Port 3080)
   │      │
   │      ├──► Meilisearch Container (Port 7700)
   │      ├──► Cosmos DB (MongoDB) (Port 10255)
   │      ├──► Redis Cache (Port 6380)
   │      └──► Blob Storage (HTTPS)
   │
   └──► Log Analytics
```

## Security

### Authentication & Authorization
- JWT-based authentication
- Secure credential storage using CREDS_KEY/CREDS_IV
- Role-based access control

### Network Security
- HTTPS only (TLS 1.2+)
- No public endpoints except Container Apps ingress
- Private communication between services
- Managed identities where possible

### Secrets Management
- All secrets stored in Container App secrets
- No secrets in environment variables
- Automatic secret rotation support
- Azure Key Vault integration (optional)

### Data Encryption
- Encryption at rest for all storage
- Encryption in transit (TLS)
- Encrypted database connections

## Scaling & Performance

### Auto-Scaling
- **Trigger**: HTTP concurrent requests
- **Threshold**: 100 concurrent requests per replica
- **Min Replicas**: 1
- **Max Replicas**: 5

### Performance Optimization
- Redis caching for frequently accessed data
- Meilisearch for fast conversation search
- Cosmos DB serverless for cost-effective scaling
- CDN integration possible for static assets

## Monitoring & Observability

### Metrics
- HTTP request count and latency
- CPU and memory usage
- Database query performance
- Redis cache hit rate

### Logs
- Application logs (stdout/stderr)
- HTTP access logs
- Error logs
- Audit logs

### Alerts (Optional)
- High error rate
- Resource exhaustion
- Service unavailability
- Anomaly detection

## Disaster Recovery

### Backup Strategy
- Cosmos DB automatic backups (every 4 hours)
- Point-in-time restore available
- Geo-replication optional for production

### High Availability
- Container Apps multi-zone deployment
- Automatic container restart on failure
- Redis persistence for session recovery

## Cost Estimation (Monthly)

**Development Environment:**
- Container Apps: ~$20-50 (varies by usage)
- Cosmos DB Serverless: ~$5-25 (pay per request)
- Redis Basic C0: ~$16
- Storage Account: ~$1-5
- Log Analytics: ~$5-20

**Total: ~$47-116/month** (varies significantly by usage)

**Production Environment:**
- Consider reserved capacity for Cosmos DB
- Upgrade Redis to Standard tier
- Increase Container Apps scale limits
- Add CDN for static content

## Deployment Topology

### Single Region (Default)
```
Region: East US
├── Container Apps Environment
├── Cosmos DB Account
├── Redis Cache
├── Storage Account
└── Log Analytics
```

### Multi-Region (Optional)
```
Primary Region: East US
├── Container Apps Environment
├── Cosmos DB Account (replicated)
└── Storage Account (replicated)

Secondary Region: West US
├── Container Apps Environment
├── Cosmos DB Account (replica)
└── Storage Account (replica)

Global:
└── Azure Front Door (traffic routing)
```

## Environment Variables

### Required (Provided by Deployment)
- `MONGO_URI`: MongoDB connection string
- `REDIS_URI`: Redis connection string
- `JWT_SECRET`: JWT signing secret
- `JWT_REFRESH_SECRET`: Refresh token secret
- `CREDS_KEY`: Credential encryption key
- `CREDS_IV`: Credential encryption IV

### Optional (Configure After Deployment)
- `OPENAI_API_KEY`: OpenAI API access
- `AZURE_OPENAI_*`: Azure OpenAI configuration
- `ANTHROPIC_API_KEY`: Anthropic Claude access
- `GOOGLE_KEY`: Google AI access

## Best Practices

1. **Security**
   - Rotate secrets regularly
   - Use managed identities
   - Enable Azure AD authentication
   - Implement network policies

2. **Performance**
   - Enable Redis persistence
   - Configure appropriate TTLs
   - Use Cosmos DB consistency levels wisely
   - Monitor and optimize queries

3. **Cost Optimization**
   - Start with serverless/basic tiers
   - Monitor usage and upgrade as needed
   - Use auto-scaling effectively
   - Clean up unused resources

4. **Operations**
   - Implement CI/CD pipelines
   - Use infrastructure as code
   - Automate testing
   - Monitor proactively

## Future Enhancements

- Azure API Management for API gateway
- Azure Front Door for global distribution
- Azure Key Vault for enhanced secret management
- Azure Monitor alerts and dashboards
- Container registry integration
- Custom domain and SSL certificates
- Azure AD B2C for enterprise authentication
