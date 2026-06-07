// Static Web App resource — content deploys via Azure/static-web-apps-deploy workflow.
//
// Provenance: originally Teknova.QuoteBuilder/infra/static-web-app.bicep. Ported
// 2026-05-25 as part of EOP Phase 1.
//
// This module provisions the SWA resource only. The build artifact upload is the
// consumer's GitHub workflow (Azure/static-web-apps-deploy).

@description('Static Web App name, e.g. teknova-orderintake-web-stage')
param name string

@description('Azure region. SWA is region-specific; co-locate with the App Service for predictable cross-traffic.')
param location string = 'westus2'

@description('SKU. Free for stage; Standard ($9/mo) for prod when SLA matters.')
@allowed([
  'Free'
  'Standard'
])
param sku string = 'Free'

@description('Public network access to the SWA. Default Enabled (unchanged behavior). Set Disabled to make the *.azurestaticapps.net default host unreachable from the public internet — for a SWA fronted by Front Door over a Private Link origin, so the FD edge becomes the only ingress. Requires Standard SKU. NOTE: with this Disabled, confirm the Azure/static-web-apps-deploy content push still succeeds (it uses the token-based deploy API, not the content host) before relying on it — this is unproven as of v1.6.0.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Resource tags.')
param tags object = {}

resource swa 'Microsoft.Web/staticSites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    stagingEnvironmentPolicy: 'Disabled' // We don't use SWA's own preview envs
    allowConfigFileUpdates: true
    publicNetworkAccess: publicNetworkAccess
  }
}

output id string = swa.id
output name string = swa.name
output defaultHostName string = swa.properties.defaultHostname
