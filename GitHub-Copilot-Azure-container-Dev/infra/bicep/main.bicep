// Main deployment template for LibreChat on Azure
targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@maxLength(8)
param environmentName string = 'dev'

@description('Application name prefix')
param appName string = 'librechat'

@description('MongoDB connection string (if using external MongoDB)')
param mongoDbConnectionString string = ''

@description('Container image tag')
param containerImageTag string = 'latest'

@description('Container registry server')
param containerRegistryServer string = ''

@description('Container registry username')
param containerRegistryUsername string = ''

@secure()
@description('Container registry password')
param containerRegistryPassword string = ''

@description('JWT secret for authentication')
@secure()
param jwtSecret string = newGuid()

@description('JWT refresh secret')
@secure()
param jwtRefreshSecret string = newGuid()

@description('CREDS_KEY for credentials encryption')
@secure()
param credsKey string = newGuid()

@description('CREDS_IV for credentials encryption')
@secure()
param credsIv string = newGuid()

// Generate unique names
var uniqueSuffix = uniqueString(resourceGroup().id)
var resourceName = '${appName}-${environmentName}-${uniqueSuffix}'

// Compute connection strings
var cosmosDbName = '${resourceName}-cosmos'
var mongoConnectionString = !empty(mongoDbConnectionString) ? mongoDbConnectionString : 'mongodb://${cosmosDbName}:[[COSMOS_KEY]]@${cosmosDbName}.mongo.cosmos.azure.com:10255/LibreChat?ssl=true&replicaSet=globaldb&retrywrites=false&maxIdleTimeMS=120000'

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${resourceName}-logs'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: '${resourceName}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Cosmos DB Account for MongoDB (if not using external MongoDB)
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = if (empty(mongoDbConnectionString)) {
  name: cosmosDbName
  location: location
  kind: 'MongoDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    capabilities: [
      {
        name: 'EnableMongo'
      }
      {
        name: 'EnableServerless'
      }
    ]
    apiProperties: {
      serverVersion: '4.2'
    }
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/mongodbDatabases@2023-04-15' = if (empty(mongoDbConnectionString)) {
  parent: cosmosAccount
  name: 'LibreChat'
  properties: {
    resource: {
      id: 'LibreChat'
    }
  }
}

// Redis Cache
resource redisCache 'Microsoft.Cache/redis@2023-08-01' = {
  name: '${resourceName}-redis'
  location: location
  properties: {
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
    }
  }
}

// Storage Account for file uploads
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: replace('${resourceName}storage', '-', '')
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// Blob Container for uploads
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource uploadsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'uploads'
  properties: {
    publicAccess: 'None'
  }
}

// Container App for LibreChat
resource librechatApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: '${resourceName}-app'
  location: location
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 3080
        transport: 'auto'
        allowInsecure: false
      }
      registries: !empty(containerRegistryServer) ? [
        {
          server: containerRegistryServer
          username: containerRegistryUsername
          passwordSecretRef: 'registry-password'
        }
      ] : []
      secrets: concat([
        {
          name: 'mongo-connection-string'
          value: !empty(mongoDbConnectionString) ? mongoDbConnectionString : replace(mongoConnectionString, '[[COSMOS_KEY]]', empty(mongoDbConnectionString) ? cosmosAccount.listKeys().primaryMasterKey : '')
        }
        {
          name: 'redis-connection-string'
          value: '${redisCache.properties.hostName}:${redisCache.properties.sslPort},password=${redisCache.listKeys().primaryKey},ssl=True,abortConnect=False'
        }
        {
          name: 'jwt-secret'
          value: jwtSecret
        }
        {
          name: 'jwt-refresh-secret'
          value: jwtRefreshSecret
        }
        {
          name: 'creds-key'
          value: credsKey
        }
        {
          name: 'creds-iv'
          value: credsIv
        }
        {
          name: 'storage-connection-string'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
      ], !empty(containerRegistryServer) ? [
        {
          name: 'registry-password'
          value: containerRegistryPassword
        }
      ] : [])
    }
    template: {
      containers: [
        {
          name: 'librechat'
          image: !empty(containerRegistryServer) ? '${containerRegistryServer}/librechat:${containerImageTag}' : 'ghcr.io/danny-avila/librechat:latest'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'HOST'
              value: '0.0.0.0'
            }
            {
              name: 'PORT'
              value: '3080'
            }
            {
              name: 'MONGO_URI'
              secretRef: 'mongo-connection-string'
            }
            {
              name: 'REDIS_URI'
              secretRef: 'redis-connection-string'
            }
            {
              name: 'JWT_SECRET'
              secretRef: 'jwt-secret'
            }
            {
              name: 'JWT_REFRESH_SECRET'
              secretRef: 'jwt-refresh-secret'
            }
            {
              name: 'CREDS_KEY'
              secretRef: 'creds-key'
            }
            {
              name: 'CREDS_IV'
              secretRef: 'creds-iv'
            }
            {
              name: 'MEILI_HOST'
              value: 'http://meilisearch:7700'
            }
            {
              name: 'MEILI_NO_ANALYTICS'
              value: 'true'
            }
            {
              name: 'AZURE_STORAGE_CONNECTION_STRING'
              secretRef: 'storage-connection-string'
            }
            {
              name: 'AZURE_STORAGE_CONTAINER_NAME'
              value: 'uploads'
            }
          ]
        }
        {
          name: 'meilisearch'
          image: 'getmeili/meilisearch:v1.5'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'MEILI_NO_ANALYTICS'
              value: 'true'
            }
            {
              name: 'MEILI_HOST'
              value: '0.0.0.0:7700'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 5
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

// Outputs
output librechatUrl string = librechatApp.properties.configuration.ingress.fqdn
output resourceGroupName string = resourceGroup().name
output containerAppName string = librechatApp.name
output cosmosAccountName string = !empty(mongoDbConnectionString) ? '' : cosmosAccount.name
output redisName string = redisCache.name
output storageAccountName string = storageAccount.name
