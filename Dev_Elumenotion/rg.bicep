targetScope = 'subscription'

param resourcegroup string
param location string = 'westus2'
param openAiService_location string = 'eastus2'

resource rg 'Microsoft.Resources/resourceGroups@2020-06-01' = {
  name: resourcegroup
  location: location
}

module resourcesDeployment './main.bicep' = {
  name: 'resourcesDeployment'
  scope: rg
  params: {
    openAiService_location: openAiService_location
    createMonogexpressAuthConfig: true
  }
}
