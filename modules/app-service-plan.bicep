// App Service Plan — parameterized SKU + instance count.
//
// Provenance: originally Teknova.QuoteBuilder/infra/app-service-plan.bicep.
// Ported 2026-05-25 as part of EOP Phase 1 to seed the alphateknova/bicep-modules
// library. See SOURCES.md for the full lineage and any subsequent changes.
//
// Usage notes:
// - One Plan is shared across Teknova apps in an environment. Cost is per-Plan
//   not per-App-Service, so shared compute is the cost-efficient shape.
// - RAM is the eventual constraint — scale up SKU when monitoring shows pressure.

@description('App Service Plan name, e.g. teknova-asp-stage')
param name string

@description('Azure region. Stay co-located with SQL and Key Vault to avoid cross-region traffic charges.')
param location string

@description('Plan SKU. S1 minimum for slot support; S2/P1V3 when more RAM or slots are needed.')
@allowed([
  'B1'
  'B2'
  'S1'
  'S2'
  'P1V3'
  'P2V3'
])
param sku string = 'S1'

@description('Number of instances. 1 is fine for stage; 2+ buys HA in prod when warranted.')
@minValue(1)
@maxValue(10)
param instanceCount int = 1

@description('Resource tags. Includes env, cost-center, owner for cost rollups.')
param tags object = {}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: instanceCount
  }
  kind: 'linux'
  properties: {
    reserved: true // Linux plan
  }
}

output id string = plan.id
output name string = plan.name
