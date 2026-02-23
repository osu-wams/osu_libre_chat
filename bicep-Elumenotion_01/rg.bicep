targetScope = 'subscription'

param resourcegroup string
param location string = 'westus2'

@description('Name of the existing Azure OpenAI instance (e.g. eastus2-dev-librechat)')
param openAiInstanceName string

@description('API key for the existing Azure OpenAI instance')
@secure()
param openAiApiKey string

resource rg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: resourcegroup
  location: location
}

module resourcesDeployment './main.bicep' = {
  name: 'resourcesDeployment'
  scope: rg
  params: {
    openAiInstanceName: openAiInstanceName
    openAiApiKey: openAiApiKey
  }
}
