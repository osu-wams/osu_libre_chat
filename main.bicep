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

@description('Mongo Express UI username')
@secure()
param mongoexpressUiUsername string

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

// Deterministic in-environment Mongo hostname (no parameter-file <suffix> needed)
var mongoHost = 'mongodb-${appSuffix}'
var mongoPort = '27017'

// ---------------------------------------------------------
// Log Analytics
// ---------------------------------------------------------
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-analytics-${appSuffix}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

// ---------------------------------------------------------
// Storage Account
// ---------------------------------------------------------
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
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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

// Create a file service for librechat-config and mongodb
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

// librechat-config file share
resource librechatConfig_fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-04-01' = {
  parent: storageAccount_fileService
  name: 'librechat-config'
  properties: {
    accessTier: 'Hot'
    shareQuota: 102400
    enabledProtocols: 'SMB'
  }
}

// Load the local librechat.yaml template
var rawLibrechatConfig = loadTextContent('./librechat.yaml')

// Replace placeholders in librechat.yaml with the existing AOAI instance info
// and the deployment names
var updatedLibrechatConfig_step1 = replace(
  rawLibrechatConfig,
  'openai-instance-name',
  openAiInstanceName
)

var updatedLibrechatConfig_step2 = replace(
  updatedLibrechatConfig_step1,
  'openai-model-router-deployment-name',
  modelRouterDeploymentName
)

var updatedLibrechatConfig_step3 = replace(
  updatedLibrechatConfig_step2,
  'openai-gpt5.2-deployment-name',
  gpt52DeploymentName
)

var updatedLibrechatConfig_step4 = replace(
  updatedLibrechatConfig_step3,
  'openai-gpt4o-mini-transcribe-deployment-name',
  gpt4oMiniTranscribeDeploymentName
)

var updatedLibrechatConfig_step5 = replace(
  updatedLibrechatConfig_step4,
  'openai-gpt4o-mini-tts-deployment-name',
  gpt4oMiniTtsDeploymentName
)

var updatedLibrechatConfig = updatedLibrechatConfig_step5

// Upload librechat.yaml to librechat-config file share
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
    scriptContent: 'printf %s "$CONTENT" > librechat.yaml && az storage file upload --source librechat.yaml -s ${librechatConfig_fileShare.name}'
  }
}

// mongodb file share
resource mongodb_fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-04-01' = {
  parent: storageAccount_fileService
  name: 'mongodb'
  properties: {
    accessTier: 'Hot'
    shareQuota: 102400
    enabledProtocols: 'SMB'
  }
}

// ---------------------------------------------------------
// Container App Environment
// ---------------------------------------------------------
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
    zoneRedundant: false
    kedaConfiguration: {}
    daprConfiguration: {}
    customDomainConfiguration: {}
    workloadProfiles: [
      {
        workloadProfileType: 'Consumption'
        name: 'Consumption'
      }
    ]
    peerAuthentication: {
      mtls: {
        enabled: false
      }
    }
  }
}

// Storage mounting for librechat-config
resource librechatConfig_environmentStorage 'Microsoft.App/managedEnvironments/storages@2023-11-02-preview' = {
  parent: containerAppEnvironment
  name: 'librechat-config'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      shareName: 'librechat-config'
      accessMode: 'ReadWrite'
      accountKey: storageAccount.listKeys().keys[0].value
    }
  }
}

// Storage mounting for mongodb
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

// ---------------------------------------------------------
// MongoDB Container App
// ---------------------------------------------------------
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

// ---------------------------------------------------------
// Mongo Express Container App
// ---------------------------------------------------------
resource mongoexpress_containerApp 'Microsoft.App/containerApps@2023-08-01-preview' = {
  name: 'mongoexpress-${appSuffix}'
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      secrets: [
        {
          name: 'mongoexpress-ui-username'
          value: mongoexpressUiUsername
        }
        {
          name: 'mongoexpress-ui-password'
          value: mongoRootPassword
        }
        {
          name: 'mongoexpress-mongo-url'
          // Silence linter: value contains a secret-derived expression; still stored as a Container App secret
          #disable-next-line use-secure-value-for-secure-inputs
          value: 'mongodb://root:${mongoRootPassword}@${mongoHost}:${mongoPort}'
        }
      ]
      ingress: {
        external: true
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
            {
              name: 'ME_CONFIG_MONGODB_URL'
              secretRef: 'mongoexpress-mongo-url'
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

// ---------------------------------------------------------
// LibreChat Container App
// ---------------------------------------------------------
resource librechat_containerApp 'Microsoft.App/containerApps@2023-08-01-preview' = {
  name: 'librechat-${appSuffix}'
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      secrets: [
        {
          name: 'openai-api-key'
          value: openAiApiKey
        }
        {
          name: 'librechat-mongo-uri'
          // Silence linter: value contains a secret-derived expression; still stored as a Container App secret
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
            {
              name: 'OPENAI_API_KEY'
              secretRef: 'openai-api-key'
            }
            {
              name: 'ASSISTANTS_MODELS'
              value: 'gpt-5.2,gpt-4o-mini-transcribe,gpt-4o-mini-tts,model-router'
            }
            {
              name: 'HELP_AND_FAQ_URL'
              value: 'https://librechat.ai'
            }
            {
              name: 'ENDPOINTS'
              value: 'assistants,azureOpenAI'
            }
            {
              name: 'OPENAI_MODELS'
              value: 'gpt-5.2,gpt-4o-mini-transcribe,gpt-4o-mini-tts,model-router'
            }
            {
              name: 'DOMAIN_CLIENT'
              value: 'http://localhost:3080'
            }
            {
              name: 'DOMAIN_SERVER'
              value: 'http://localhost:3080'
            }
            {
              name: 'DEBUG_LOGGING'
              value: 'false'
            }
            {
              name: 'DEBUG_CONSOLE'
              value: 'false'
            }
            {
              name: 'CONFIG_PATH'
              value: '/app/config-env/librechat.yaml'
            }
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
            {
              name: 'ALLOW_EMAIL_LOGIN'
              value: 'true'
            }
            {
              name: 'ALLOW_REGISTRATION'
              value: 'true'
            }
            {
              name: 'SESSION_EXPIRY'
              value: '1000 * 60 * 15'
            }
            {
              name: 'REFRESH_TOKEN_EXPIRY'
              value: '(1000 * 60 * 60 * 24) * 7'
            }
            {
              name: 'DEBUG_OPENAI'
              value: 'false'
            }
            {
              name: 'CUSTOM_FOOTER'
              value: 'That Dam BeavrChat ∞ is powered by LibreChat and Azure OpenAI.'
            }
            {
              name: 'NO_INDEX'
              value: 'true'
            }
            {
              name: 'ALLOW_SHARED_LINKS_PUBLIC'
              value: 'false'
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
