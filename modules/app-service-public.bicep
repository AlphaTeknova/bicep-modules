// App Service with PUBLIC network ingress — parameterized name, runtime, app settings, and Key Vault refs.
//
// Provenance: originally Teknova.QuoteBuilder/infra/app-service.bicep. Ported and renamed
// 2026-05-25 as part of EOP Phase 1. The "-public" suffix marks the explicit public
// exposure required by Dep §5.5 ("if a resource is publicly reachable, the module name
// must say so"). For the more common backend-with-private-endpoint case, see
// app-service-with-pe.bicep (added in EOP Phase 3).
//
// Usage notes:
// - HTTPS-only enforced; TLS 1.2 minimum; FTPS disabled; HTTP/2 on.
// - System-assigned managed identity; grant Key Vault `get` on secrets separately.
// - Health-check path matches App §11 (/health). Override via param for legacy apps.
// - App settings merge plain + Key Vault references; KV refs use
//   @Microsoft.KeyVault(SecretUri=https://{vault}.vault.azure.net/secrets/{name}/)

@description('App Service name, e.g. teknova-orderintake-api-stage')
param name string

@description('Azure region.')
param location string

@description('Resource ID of the parent App Service Plan.')
param planId string

@description('.NET (or other) runtime stack — e.g. DOTNETCORE|10.0')
param linuxFxVersion string = 'DOTNETCORE|10.0'

@description('App settings (plain key-value, non-secret). For secrets use keyVaultReferences.')
param appSettings object = {}

@description('Key Vault secret references. Map of app-setting-key -> @Microsoft.KeyVault(...) value.')
param keyVaultReferences object = {}

@description('Connection strings. Map of name -> { value: ..., type: SQLAzure|MySql|... }.')
param connectionStrings object = {}

@description('Health check path. Standards §11 says /health unconditionally.')
param healthCheckPath string = '/health'

@description('Resource IDs of user-assigned managed identities to attach. Default empty = system-assigned only. When supplied, the site carries `SystemAssigned, UserAssigned` so existing SAMI-based RBAC keeps working alongside the durable UAMIs. Pair with an `AZURE_CLIENT_ID` app setting pointing at the chosen UAMI so DefaultAzureCredential picks it deterministically.')
param userAssignedIdentityIds string[] = []

@description('Resource tags.')
param tags object = {}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux'
  identity: empty(userAssignedIdentityIds) ? {
    type: 'SystemAssigned'
  } : {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: toObject(userAssignedIdentityIds, id => id, id => {})
  }
  properties: {
    serverFarmId: planId
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      healthCheckPath: healthCheckPath
      appSettings: [for setting in items(union(appSettings, keyVaultReferences)): {
        name: setting.key
        value: setting.value
      }]
      connectionStrings: [for cs in items(connectionStrings): {
        name: cs.key
        connectionString: cs.value.value
        type: cs.value.type
      }]
    }
  }
}

output id string = app.id
output name string = app.name
output principalId string = app.identity.principalId
output defaultHostName string = app.properties.defaultHostName
