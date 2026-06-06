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
// - Public-network access: `publicNetworkAccess: 'Enabled'` with the main-site
//   default action governed by `ipSecurityRestrictionsDefaultAction` (default
//   `'Deny'`, no `ipSecurityRestrictions` entries). Default effect: runtime is
//   unreachable from the public internet — every public-IP request gets a 403,
//   and PE-inbound traffic bypasses access restrictions per Azure docs, so
//   runtime is effectively PE-only. Set the param to `'Allow'` for an
//   Entra-gated public surface (browser-reached internal app with no App Gateway
//   front; Entra is the gate). SCM/Kudu uses its own rule set
//   (`scmIpSecurityRestrictionsUseMain: false`, default Allow) so GitHub-hosted
//   runners can OneDeploy to the public SCM endpoint — OIDC/MSI auth gates write
//   access. Replaces the prior `publicNetworkAccess: 'Disabled'` setting that
//   also blocked SCM and broke CI (the "Ip Forbidden 403" failure on the
//   GitHub-hosted runner). When the Phase 4 self-hosted-runner-in-hub-VNet
//   lands, a deny-default app can flip `publicNetworkAccess` back to 'Disabled'
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

@description('Resource IDs of user-assigned managed identities to attach. Default empty = system-assigned only. When supplied, the site carries `SystemAssigned, UserAssigned` so existing SAMI-based RBAC keeps working alongside the durable UAMIs. Pair with an `AZURE_CLIENT_ID` app setting pointing at the chosen UAMI so DefaultAzureCredential picks it deterministically.')
param userAssignedIdentityIds string[] = []

@description('Startup command line for the container. Default empty leaves Oryx auto-detection in place. Set explicitly (e.g. `dotnet Teknova.SomeApp.dll`) to skip Oryx — auto-detect is unreliable inside the warmup probe budget for renamed assemblies.')
param appCommandLine string = ''

@description('Cold-start container warmup limit (seconds), surfaced as the WEBSITES_CONTAINER_START_TIME_LIMIT app setting. Default 600 matches what CPQ found necessary in practice — Azure platform default of 230s busts cert rehash + Oryx detect on B1.')
@minValue(60)
@maxValue(1800)
param containerStartTimeLimitSeconds int = 600

@description('Managed identity used by the App Service platform to resolve @Microsoft.KeyVault(...) app-setting references. Default empty = system-assigned. REQUIRED when the app carries a user-assigned identity AND uses keyVaultReferences: platform KV-reference resolution defaults to the system-assigned MI, which typically has no KV RBAC (only the UAMI is granted Secrets User) — leaving the references unresolved (red X in the portal). Set to the UAMI resource ID. CPQ Phase 3a hit this on the Canary token reference.')
param keyVaultReferenceIdentity string = ''

@description('Default action for the MAIN-SITE (runtime) IP access restrictions. Default `Deny` = the standard PE-only backend posture per Dep §5.1: public-IP requests get a 403 and the runtime is reachable only via the inbound private endpoint (PE traffic bypasses access restrictions). Set `Allow` to make the runtime publicly reachable over HTTPS — for Entra-gated internal surfaces reached directly by browsers without an App Gateway front, where Entra (MSAL/JWT + Conditional Access) is the auth gate rather than the network (see consumer deviation, e.g. CPQ D15). SCM/Kudu keeps its own Allow-default rules regardless of this value.')
@allowed([
  'Allow'
  'Deny'
])
param ipSecurityRestrictionsDefaultAction string = 'Deny'

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
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: empty(keyVaultReferenceIdentity) ? null : keyVaultReferenceIdentity
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
      appCommandLine: appCommandLine
      vnetRouteAllEnabled: true
      // Runtime access restrictions. Default-deny (PE-inbound only; PE traffic
      // bypasses these per Azure docs) unless the consumer opts into `Allow` for
      // an Entra-gated public surface. SCM keeps its own (Allow-default) rules so
      // GitHub-hosted runners can deploy regardless.
      ipSecurityRestrictionsDefaultAction: ipSecurityRestrictionsDefaultAction
      ipSecurityRestrictions: []
      scmIpSecurityRestrictionsUseMain: false
      scmIpSecurityRestrictionsDefaultAction: 'Allow'
      scmIpSecurityRestrictions: []
      appSettings: [for setting in items(union(appSettings, keyVaultReferences, {
        WEBSITES_CONTAINER_START_TIME_LIMIT: string(containerStartTimeLimitSeconds)
      })): {
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
