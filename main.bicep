param appSuffix string = uniqueString(resourceGroup().id)
param containerAppEnvrionmentName string = 'managedEnvironment-${appSuffix}'
param location string = resourceGroup().location

@description('Name of the existing Azure OpenAI instance (the subdomain part, e.g. eastus2-dev-librechat)')
param openAiInstanceName string

@description('API key for the existing Azure OpenAI instance')
@secure()
param openAiApiKey string

@description('Deployment name for the model-router deployment in Azure OpenAI')
param modelRouterDeploymentName string = 'model-router'

@description('Deployment name for the gpt-5.2 deployment in Azure OpenAI')
param gpt52DeploymentName string = 'gpt-5.2'

@description('Deployment name for the gpt-4o-mini-transcribe deployment in Azure OpenAI')
param gpt4oMiniTranscribeDeploymentName string = 'gpt-4o-mini-transcribe'

@description('Deployment name for the gpt-4o-mini-tts deployment in Azure OpenAI')
param gpt4oMiniTtsDeploymentName string = 'gpt-4o-mini-tts'

@description('MongoDB root password')
@secure()
param mongoRootPassword string

@description('LibreChat credentials encryption key')
@secure()
param librechatCredsKey string

@description('LibreChat credentials encryption IV')
@secure()
param librechatCredsIv string

@description('LibreChat JWT secret')
@secure()
param librechatJwtSecret string

@description('LibreChat JWT refresh secret')
@secure()
param librechatJwtRefreshSecret string

// -----------------------------------------------------------------------------
// Azure Entra / OpenID parameters (single-tenant)
// -----------------------------------------------------------------------------
@description('Azure Entra app client ID (OIDC)')
@secure()
param azureOpenIdClientId string

@description('Azure Entra app client secret (OIDC)')
@secure()
param azureOpenIdClientSecret string

@description('Azure Entra tenant ID (OIDC issuer)')
param azureOpenIdTenantId string

@description('A random session secret used for OpenID sessions (e.g. cookie encryption)')
@secure()
param openIdSessionSecret string

@description('Optional: the JSON path inside a token where required roles reside (default: "roles")')
param openIdRequiredRoleParameterPath string = 'roles'

@description('Optional: comma-separated names of groups/roles in Entra that users must belong to')
param openIdRequiredRole string = ''

// -----------------------------------------------------------------------------
// SharePoint Integration Parameters
// -----------------------------------------------------------------------------
@description('Base URL of the SharePoint tenant (e.g., https://contoso.sharepoint.com)')
param sharePointBaseUrl string

@description('Scope for SharePoint picker (SharePoint API)')
param sharePointPickerSharePointScope string

@description('Scope for file downloads (Microsoft Graph API)')
param sharePointPickerGraphScope string = 'Files.Read.All'

// Determine the deterministic MongoDB host name
var mongoHost = 'mongodb-${appSuffix}'
var mongoPort = '27017'

// -----------------------------------------------------------------------------
// Log Analytics Workspace
// -----------------------------------------------------------------------------
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-analytics-${appSuffix}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

// -----------------------------------------------------------------------------
// Storage Account (unchanged for brevity — see prior version)
// -----------------------------------------------------------------------------
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: 'storage${appSuffix}'
  location: location
  sku: {
    name: 'Standard_RAGRS'
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'    // Consider hardening later
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true        // For demo; consider MI later
    largeFileSharesState: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource storageAccount_fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-04-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {}
    }
    cors: {
      corsRules: []
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource librechatConfig_fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-04-01' = {
  parent: storageAccount_fileService
  name: 'librechat-config'
  properties: {
    accessTier: 'Hot'
    shareQuota: 102400
    enabledProtocols: 'SMB'
  }
}

// -----------------------------------------------------------------------------
// Load librechat.yaml template and perform placeholder replacements
// -----------------------------------------------------------------------------
var rawLibrechatConfig = loadTextContent('./librechat.yaml')

// Replace placeholders in librechat.yaml with OpenAI instance and deployment names.
// Note: We no longer substitute the OpenAI key because it is injected via secret.
// The YAML should leave apiKey blank.
var updatedLibrechatConfig_1 = replace(rawLibrechatConfig, 'openai-instance-name', openAiInstanceName)
var updatedLibrechatConfig_2 = replace(updatedLibrechatConfig_1, 'openai-model-router-deployment-name', modelRouterDeploymentName)
var updatedLibrechatConfig_3 = replace(updatedLibrechatConfig_2, 'openai-gpt5.2-deployment-name', gpt52DeploymentName)
var updatedLibrechatConfig_4 = replace(updatedLibrechatConfig_3, 'openai-gpt4o-mini-transcribe-deployment-name', gpt4oMiniTranscribeDeploymentName)
var updatedLibrechatConfig_5 = replace(updatedLibrechatConfig_4, 'openai-gpt4o-mini-tts-deployment-name', gpt4oMiniTtsDeploymentName)
var updatedLibrechatConfig = updatedLibrechatConfig_5

resource uploadLibrechatConfig_deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'upload-librechat-config-${appSuffix}'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.59.0'
    timeout: 'PT5M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'AZURE_STORAGE_ACCOUNT'
        value: storageAccount.name
      }
      {
        name: 'AZURE_STORAGE_KEY'
        secureValue: storageAccount.listKeys().keys[0].value
      }
      {
        name: 'CONTENT'
        value: updatedLibrechatConfig
      }
    ]
    scriptContent: '
      printf %s "$CONTENT" > librechat.yaml
      az storage file upload --source librechat.yaml -s ${librechatConfig_fileShare.name}
    '
  }
}

// -----------------------------------------------------------------------------
// MongoDB file share for database storage (unchanged)
// -----------------------------------------------------------------------------
resource mongodb_fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-04-01' = {
  parent: storageAccount_fileService
  name: 'mongodb'
  properties: {
    accessTier: 'Hot'
    shareQuota: 102400
    enabledProtocols: 'SMB'
  }
}

// -----------------------------------------------------------------------------
// Container App Environment (unchanged for brevity)
// -----------------------------------------------------------------------------
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
  name: containerAppEnvrionmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    // Additional environment settings omitted for brevity
    zoneRedundant: false
    workloadProfiles: [
      {
        workloadProfileType: 'Consumption'
        name: 'Consumption'
      }
    ]
  }
}

// Storage mounts in environment for librechat config and MongoDB (remains read-write)
resource librechatConfig_environmentStorage 'Microsoft.App/managedEnvironments/storages@2023-11-02-preview' = {
  parent: containerAppEnvironment
  name: 'librechat-config'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      shareName: 'librechat-config'
      accessMode: 'ReadWrite' // consider ReadOnly in future hardening
      accountKey: storageAccount.listKeys().keys[0].value
    }
  }
}

resource mongodb_environmentStorage 'Microsoft.App/managedEnvironments/storages@2023-11-02-preview' = {
  parent: containerAppEnvironment
  name: 'mongodb'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      shareName: 'mongodb'
      accessMode: 'ReadWrite'
      accountKey: storageAccount.listKeys().keys[0].value
    }
  }
}

// -----------------------------------------------------------------------------
// MongoDB container app (unchanged for brevity)
// -----------------------------------------------------------------------------
resource mongodb_containerApp 'Microsoft.App/containerApps@2023-08-01-preview' = {
  name: 'mongodb-${appSuffix}'
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      secrets: [
        {
          name: 'mongo-root-password'
          value: mongoRootPassword
        }
      ]
      ingress: {
        external: false
        transport: 'tcp'
        targetPort: 27017
        exposedPort: 27017
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'mongodb-${appSuffix}'
          image: 'bitnami/mongodb:latest'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'MONGODB_ROOT_USER'
              value: 'root'
            }
            {
              name: 'MONGODB_ROOT_PASSWORD'
              secretRef: 'mongo-root-password'
            }
          ]
          volumeMounts: [
            {
              volumeName: 'mongodb'
              mountPath: '/bitnami/mongodb'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          storageType: 'AzureFile'
          name: 'mongodb'
          storageName: mongodb_environmentStorage.name
          mountOptions: 'dir_mode=0777,file_mode=0777,uid=1001,gid=1001,mfsymlinks'
        }
      ]
    }
  }
}

// -----------------------------------------------------------------------------
// Mongo Express container app with basic auth and secret wiring
// -----------------------------------------------------------------------------
resource mongoexpress_containerApp 'Microsoft.App/containerApps@2023-08-01-preview' = {
  name: 'mongoexpress-${appSuffix}'
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      secrets: [
        {
          name: 'mongoexpress-ui-username'
          value: 'imperator'        // or use a secure parameter in future
        }
        {
          name: 'mongoexpress-ui-password'
          value: mongoRootPassword
        }
        {
          name: 'mongoexpress-mongo-url'
          #disable-next-line use-secure-value-for-secure-inputs
          value: 'mongodb://root:${mongoRootPassword}@${mongoHost}:${mongoPort}'
        }
      ]
      ingress: {
        external: false     // internal only for security; change to true if required
        transport: 'http'
        targetPort: 8081
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'mongoexpress-${appSuffix}'
          image: 'mongo-express'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'ME_CONFIG_MONGODB_URL'
              secretRef: 'mongoexpress-mongo-url'
            }
            {
              name: 'ME_CONFIG_BASICAUTH'
              value: 'true'
            }
            {
              name: 'ME_CONFIG_BASICAUTH_USERNAME'
              secretRef: 'mongoexpress-ui-username'
            }
            {
              name: 'ME_CONFIG_BASICAUTH_PASSWORD'
              secretRef: 'mongoexpress-ui-password'
            }
            {
              name: 'ME_CONFIG_MONGODB_ENABLE_ADMIN'
              value: 'true'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// -----------------------------------------------------------------------------
// LibreChat container app with Entra authentication, token reuse, Graph & SharePoint integration
// -----------------------------------------------------------------------------
resource librechat_containerApp 'Microsoft.App/containerApps@2023-08-01-preview' = {
  name: 'librechat-${appSuffix}'
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      secrets: [
        {
          name: 'librechat-mongo-uri'
          #disable-next-line use-secure-value-for-secure-inputs
          value: 'mongodb://root:${mongoRootPassword}@${mongoHost}:${mongoPort}'
        }
        {
          name: 'librechat-creds-key'
          value: librechatCredsKey
        }
        {
          name: 'librechat-creds-iv'
          value: librechatCredsIv
        }
        {
          name: 'librechat-jwt-secret'
          value: librechatJwtSecret
        }
        {
          name: 'librechat-jwt-refresh-secret'
          value: librechatJwtRefreshSecret
        }
        // OpenID/Entra secrets
        {
          name: 'azure-openid-client-id'
          value: azureOpenIdClientId
        }
        {
          name: 'azure-openid-client-secret'
          value: azureOpenIdClientSecret
        }
        {
          name: 'open-id-session-secret'
          value: openIdSessionSecret
        }
        // SharePoint tenant URL as secret (if sensitive)
        {
          name: 'sharepoint-base-url'
          value: sharePointBaseUrl
        }
      ]
      ingress: {
        external: true
        transport: 'http'
        targetPort: 3080
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'librechat-${appSuffix}'
          image: 'librechat/librechat:v0.8.2'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            // ----------------------------------------------------------------
            // LibreChat core settings (unchanged models)
            {
              name: 'ASSISTANTS_MODELS'
              value: 'gpt-5.2,gpt-4o-mini-transcribe,gpt-4o-mini-tts,model-router'
            }
            {
              name: 'OPENAI_MODELS'
              value: 'gpt-5.2,gpt-4o-mini-transcribe,gpt-4o-mini-tts,model-router'
            }
            {
              name: 'ENDPOINTS'
              value: 'assistants,azureOpenAI'
            }
            {
              name: 'CONFIG_PATH'
              value: '/app/config-env/librechat.yaml'
            }
            // ----------------------------------------------------------------
            // MongoDB & App secrets
            {
              name: 'MONGO_URI'
              secretRef: 'librechat-mongo-uri'
            }
            {
              name: 'CREDS_KEY'
              secretRef: 'librechat-creds-key'
            }
            {
              name: 'CREDS_IV'
              secretRef: 'librechat-creds-iv'
            }
            {
              name: 'JWT_SECRET'
              secretRef: 'librechat-jwt-secret'
            }
            {
              name: 'JWT_REFRESH_SECRET'
              secretRef: 'librechat-jwt-refresh-secret'
            }
            // ----------------------------------------------------------------
            // Disable local login & enable social login (Entra Only)
            {
              name: 'ALLOW_EMAIL_LOGIN'
              value: 'false'
            }
            {
              name: 'ALLOW_REGISTRATION'
              value: 'false'
            }
            {
              name: 'ALLOW_SOCIAL_LOGIN'
              value: 'true'
            }
            // Domain configuration (update with your external domain or keep localhost)
            {
              name: 'DOMAIN_CLIENT'
              value: 'http://localhost:3080'
            }
            {
              name: 'DOMAIN_SERVER'
              value: 'http://localhost:3080'
            }
            // ----------------------------------------------------------------
            // OpenID/OIDC variables for Azure Entra ID (single tenant)
            {
              name: 'OPENID_CLIENT_ID'
              secretRef: 'azure-openid-client-id'
            }
            {
              name: 'OPENID_CLIENT_SECRET'
              secretRef: 'azure-openid-client-secret'
            }
            {
              name: 'OPENID_ISSUER'
              value: 'https://login.microsoftonline.com/${azureOpenIdTenantId}/v2.0/'
            }
            {
              name: 'OPENID_SESSION_SECRET'
              secretRef: 'open-id-session-secret'
            }
            {
              name: 'OPENID_SCOPE'
              value: 'openid profile email offline_access'
            }
            {
              name: 'OPENID_CALLBACK_URL'
              value: '/oauth/openid/callback'
            }
            {
              name: 'OPENID_REQUIRED_ROLE_TOKEN_KIND'
              value: 'id'
            }
            {
              name: 'OPENID_REQUIRED_ROLE_PARAMETER_PATH'
              value: openIdRequiredRoleParameterPath
            }
            {
              name: 'OPENID_REQUIRED_ROLE'
              value: openIdRequiredRole
            }
            {
              name: 'OPENID_USE_END_SESSION_ENDPOINT'
              value: 'true'
            }
            // ----------------------------------------------------------------
            // Token reuse configuration & JWKS caching
            {
              name: 'OPENID_REUSE_TOKENS'
              value: 'true'
            }
            {
              name: 'OPENID_JWKS_URL_CACHE_ENABLED'
              value: 'true'
            }
            {
              name: 'OPENID_JWKS_URL_CACHE_TIME'
              value: '600000' // 10 minutes in ms
            }
            {
              name: 'OPENID_ON_BEHALF_FLOW_FOR_USERINFO_REQUIRED'
              value: 'true'
            }
            {
              name: 'OPENID_ON_BEHALF_FLOW_USERINFO_SCOPE'
              value: 'user.read'
            }
            // ----------------------------------------------------------------
            // Graph people / group search integration
            {
              name: 'USE_ENTRA_ID_FOR_PEOPLE_SEARCH'
              value: 'true'
            }
            {
              name: 'ENTRA_ID_INCLUDE_OWNERS_AS_MEMBERS'
              value: 'true'
            }
            {
              name: 'OPENID_GRAPH_SCOPES'
              value: 'User.Read,People.Read,GroupMember.Read.All,User.ReadBasic.All'
            }
            // ----------------------------------------------------------------
            // SharePoint / OneDrive integration
            {
              name: 'ENABLE_SHAREPOINT_FILEPICKER'
              value: 'true'
            }
            {
              name: 'SHAREPOINT_BASE_URL'
              secretRef: 'sharepoint-base-url'
            }
            {
              name: 'SHAREPOINT_PICKER_SHAREPOINT_SCOPE'
              value: sharePointPickerSharePointScope
            }
            {
              name: 'SHAREPOINT_PICKER_GRAPH_SCOPE'
              value: sharePointPickerGraphScope
            }
            // ----------------------------------------------------------------
            // Operational defaults (already hardened)
            {
              name: 'DEBUG_LOGGING'
              value: 'false'
            }
            {
              name: 'DEBUG_CONSOLE'
              value: 'false'
            }
            {
              name: 'DEBUG_OPENAI'
              value: 'false'
            }
            {
              name: 'HELP_AND_FAQ_URL'
              value: 'https://librechat.ai'
            }
            {
              name: 'CUSTOM_FOOTER'
              value: 'ChatGPT can make mistakes. Check important info.'
            }
            {
              name: 'NO_INDEX'
              value: 'true'
            }
            {
              name: 'ALLOW_SHARED_LINKS_PUBLIC'
              value: 'false'
            }
            {
              name: 'SESSION_EXPIRY'
              value: '1000 * 60 * 15'
            }
            {
              name: 'REFRESH_TOKEN_EXPIRY'
              value: '(1000 * 60 * 60 * 24) * 7'
            }
          ]
          volumeMounts: [
            {
              volumeName: 'librechat-config'
              mountPath: '/app/config-env/'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          storageType: 'AzureFile'
          name: 'librechat-config'
          storageName: librechatConfig_environmentStorage.name
          mountOptions: 'dir_mode=0777,file_mode=0777,uid=1001,gid=1001,mfsymlinks'
        }
      ]
    }
  }
}
