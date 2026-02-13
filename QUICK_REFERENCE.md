# Quick Reference - LibreChat on Azure

## 🚀 One-Command Deployment

```bash
export RESOURCE_GROUP_NAME="librechat-rg"
export LOCATION="eastus"
export ENVIRONMENT="dev"
./infra/deploy.sh
```

## 📋 Common Commands

### Deploy
```bash
./infra/deploy.sh
```

### View Logs
```bash
az containerapp logs show -n <app-name> -g librechat-rg --follow
```

### Update Environment Variables
```bash
az containerapp update -n <app-name> -g librechat-rg \
  --set-env-vars "OPENAI_API_KEY=secretref:openai-key" \
  --secrets "openai-key=sk-your-key"
```

### Scale Application
```bash
az containerapp update -n <app-name> -g librechat-rg \
  --min-replicas 2 --max-replicas 10
```

### Get Application URL
```bash
az containerapp show -n <app-name> -g librechat-rg \
  --query properties.configuration.ingress.fqdn -o tsv
```

### Delete Resources
```bash
az group delete --name librechat-rg --yes
```

## 🔧 Configuration Files

| File | Purpose |
|------|---------|
| `infra/bicep/main.bicep` | Main infrastructure template |
| `infra/bicep/parameters.dev.json` | Dev environment parameters |
| `infra/bicep/parameters.prod.json` | Prod environment parameters |
| `infra/deploy.sh` | Automated deployment script |
| `Dockerfile` | Container image definition |
| `librechat.yaml` | LibreChat configuration |
| `.env.template` | Environment variables template |

## 📊 Azure Resources Created

1. **Container Apps Environment** - Hosting platform
2. **Container App** - LibreChat + Meilisearch
3. **Cosmos DB** - MongoDB-compatible database
4. **Redis Cache** - Session management
5. **Storage Account** - File uploads
6. **Log Analytics** - Monitoring

## 💰 Cost Estimates

**Development:** ~$47-116/month
**Production:** ~$150-300/month (scaled up)

## 🔐 Security Checklist

- [x] HTTPS enforced
- [x] TLS 1.2+ for all connections
- [x] Secrets in Container App secrets
- [x] Private blob storage
- [x] Network isolation
- [ ] Azure AD authentication (optional)
- [ ] Custom domain (optional)
- [ ] WAF/DDoS protection (optional)

## 🔗 Quick Links

- **LibreChat Docs:** https://www.librechat.ai/docs
- **Azure Container Apps:** https://learn.microsoft.com/azure/container-apps/
- **Bicep Docs:** https://learn.microsoft.com/azure/azure-resource-manager/bicep/

## ⚡ Troubleshooting

| Issue | Solution |
|-------|----------|
| Container won't start | Check logs with `az containerapp logs show` |
| Database connection fails | Verify Cosmos DB is running and connection string is correct |
| High costs | Review scaling settings and consider serverless/basic tiers |
| File uploads fail | Check storage account connection string and container permissions |

## 📝 Environment Variables

### Required (Auto-configured)
- `MONGO_URI` - MongoDB connection
- `REDIS_URI` - Redis connection
- `JWT_SECRET` - Authentication secret
- `CREDS_KEY`, `CREDS_IV` - Encryption keys

### Optional (Configure after deployment)
- `OPENAI_API_KEY` - OpenAI access
- `AZURE_OPENAI_API_KEY` - Azure OpenAI
- `ANTHROPIC_API_KEY` - Claude access
- `GOOGLE_KEY` - Google AI access

## 🎯 Next Steps After Deployment

1. ✅ Access the application URL
2. ✅ Create first user account
3. ✅ Configure AI provider API keys
4. ✅ Test file upload functionality
5. ✅ Configure custom domain (optional)
6. ✅ Set up monitoring alerts
7. ✅ Disable registration (for production)
