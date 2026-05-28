// App Service (Linux) with VNet integration outbound + private endpoint inbound.
//
// Fresh write (no QB lineage). QB only had a public-ingress App Service module.
// The PE variant is the default per Dep §5.1 — backends sit behind the shared
// App Gateway in the hub, never publicly reachable on *.azurewebsites.net.
//
// Usage notes:
// - System-assigned MSI on by default. Grant RBAC to KV / SQL / SB / Blob
//   separately against the output `principalId`.
// - VNet integration uses the `vnetIntegrationSubnetId` for OUTBOUND traffic
//   (to reach SQL PE, KV PE, SB PE). The inbound PE lives in `privateEndpointSubnetId`.
//   These can be the same subnet, or different — the per-app /26 model puts both
//   in the app's own subnet for simplicity.
// - Health-check path defaults to /health (App §11). Note App vs Dep §7.2
//   disagreement on /health vs /healthz; this module follows App §11.
// - Public-network access: `publicNetworkAccess: 'Enabled'` with
//   `ipSecurityRestrictionsDefaultAction: 'Deny'` (no `ipSecurityRestrictions`
//   entries). Effect: runtime is unreachable from the public internet — every
//   public-IP request gets a 403. PE-inbound traffic bypasses access
//   restrictions per Azure docs, so runtime is effectively PE-only.
//   SCM/Kudu uses its own rule set (`scmIpSecurityRestrictionsUseMain: false`,
//   default Allow) so GitHub-hosted runners can OneDeploy to the public SCM
//   endpoint — OIDC/MSI auth gates write access. Replaces the prior
//   `publicNetworkAccess: 'Disabled'` setting that also blocked SCM and broke
//   CI (the "Ip Forbidden 403" failure on the GitHub-hosted runner). When the
//   Phase 4 self-hosted-runner-in-hub-VNet lands, flip this back to 'Disabled'
//   and remove the SCM allow.

@description('App Service name, e.g. tk-com-orderintake-stage-api. Globally unique.')
param name string

@description('Azure region.')
param location string

@description('Resource ID of the parent App Service Plan (must be Linux).')
param planId string

@description('Linux runtime stack — e.g. DOTNETCORE|10.0')
param linuxFxVersion string = 'DOTNETCORE|10.0'

@description('App settings (plain key-value, non-secret). For secrets use keyVaultReferences.')
param appSettings object = {}

@description('Key Vault secret references. Map of app-setting-key -> @Microsoft.KeyVault(...) value.')
param keyVaultReferences object = {}

@description('Connection strings. Map of name -> { value: ..., type: SQLAzure|... }.')
param connectionStrings object = {}

@description('Health check path. Standards App §11 says /health.')
param healthCheckPath string = '/health'

@description('Resource ID of the subnet used for OUTBOUND VNet integration (regional).')
param vnetIntegrationSubnetId string

@description('Resource ID of the subnet that will host the INBOUND PE NIC. May equal vnetIntegrationSubnetId.')
param privateEndpointSubnetId string

@description('Resource ID of the privatelink.azurewebsites.net private DNS zone.')
param privateDnsZoneId string

@description('Resource ID of the Log Analytics workspace for diagnostic settings.')
param logAnalyticsWorkspaceId string = ''

@description('Resource tags.')
param tags object = {}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: planId
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
    virtualNetworkSubnetId: vnetIntegrationSubnetId
    // vnetRouteAllEnabled lives in siteConfig only — see below. The legacy
    // properties-level alias is silently accepted by some API versions and
    // ignored by others; removing it avoids drift when the alias is dropped.
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      healthCheckPath: healthCheckPath
      vnetRouteAllEnabled: true
      // Runtime is locked down to PE-inbound only via deny-default access
      // restrictions. PE traffic bypasses these per Azure docs. SCM keeps
      // its own (Allow-default) rules so GitHub-hosted runners can deploy.
      ipSecurityRestrictionsDefaultAction: 'Deny'
      ipSecurityRestrictions: []
      scmIpSecurityRestrictionsUseMain: false
      scmIpSecurityRestrictionsDefaultAction: 'Allow'
      scmIpSecurityRestrictions: []
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

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${name}-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-plsc'
        properties: {
          privateLinkServiceId: app.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sites'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${name}-diag'
  scope: app
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output id string = app.id
output name string = app.name
output principalId string = app.identity.principalId
output defaultHostName string = app.properties.defaultHostName
