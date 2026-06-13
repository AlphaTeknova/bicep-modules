// Azure SQL Server with private endpoint, AAD-only auth, no firewall rules.
//
// Fresh write (no QB lineage). QB's sql-server.bicep was rejected for v0.1.0-pre
// because it had publicNetworkAccess: 'Enabled', an AllowAllAzureIps firewall
// rule, and SQL-auth admin login + password. This module is the standards-
// conforming replacement per Dep §5.1 (PE-only) and Dep §6.1 (Entra-only).
//
// Usage notes:
// - publicNetworkAccess is 'Disabled' — the PE is the only path. No firewall
//   rules are created; setting any would defeat the network isolation.
// - administratorLogin / administratorLoginPassword are intentionally NOT
//   parameters. The only admin path is the AAD admin group passed in
//   aadAdminGroupObjectId / aadAdminGroupName. azureADOnlyAuthentication is
//   enforced via the child azureADOnlyAuthentications resource.
// - The DB itself is not provisioned here — pair this module with the seeded
//   sql-database.bicep, passing this server's `name` output as `sqlServerName`.
// - DNS A-record is created in the privatelink.database.windows.net zone the
//   caller passes in. The zone must already exist in the hub shared-infra.

@description('SQL server name, e.g. tk-com-orderintake-stage-sql. Must be globally unique.')
param name string

@description('Azure region.')
param location string

@description('Object ID of the Entra group that will be SQL admin (e.g. Teknova-OrderIntake-SQL-Admins).')
param aadAdminGroupObjectId string

@description('Display name of the Entra admin group. Stored on the server for visibility; the object ID is what authorizes.')
param aadAdminGroupName string

@description('Resource ID of the subnet that will host the private endpoint NIC.')
param privateEndpointSubnetId string

@description('Resource ID of the privatelink.database.windows.net private DNS zone (lives in the hub).')
param privateDnsZoneId string

@description('Public network access. Default Disabled (PE-only). Stage sets Enabled for the CPQ hybrid migration posture — GitHub-hosted runners apply EF bundles over a transient firewall rule. azureADOnlyAuthentication stays the real barrier either way (a stale rule or the public TDS endpoint grants nothing without an AAD token). (EOP Phase 10 arch-review B3.)')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('Resource tags.')
param tags object = {}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // No administratorLogin / administratorLoginPassword. SQL-auth is disabled
    // by the child azureADOnlyAuthentications resource below.
    version: '12.0'
    publicNetworkAccess: publicNetworkAccess
    minimalTlsVersion: '1.2'
    restrictOutboundNetworkAccess: 'Disabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'Group'
      login: aadAdminGroupName
      sid: aadAdminGroupObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

// Belt-and-braces: also set AAD-only on the dedicated resource. Some control-plane
// paths read this child resource rather than the parent's `administrators` block.
resource aadOnly 'Microsoft.Sql/servers/azureADOnlyAuthentications@2023-08-01-preview' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    azureADOnlyAuthentication: true
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
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
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
        name: 'sql'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output id string = sqlServer.id
output name string = sqlServer.name
output fqdn string = sqlServer.properties.fullyQualifiedDomainName
output principalId string = sqlServer.identity.principalId
