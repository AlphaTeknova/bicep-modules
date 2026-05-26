// Azure Key Vault with RBAC auth, PE, soft-delete + purge protection.
//
// Fresh write (no QB lineage). QB's key-vault.bicep was an `existing`-only
// reference, not a creator module. This is the creator that satisfies
// Dep §6.3 (RBAC, not access policies) and Dep §5.1 (PE-only).
//
// Usage notes:
// - enableRbacAuthorization: true is non-negotiable. Consumers grant
//   `Key Vault Secrets User` (or similar) RBAC to MSIs on the output `id`.
// - enabledForDeployment / enabledForTemplateDeployment are FALSE. App Service
//   reads secrets at runtime via @Microsoft.KeyVault(SecretUri=...) using MSI,
//   not ARM template inline-reference.
// - Soft-delete retention is 90 days; purge protection is enabled. Both are
//   one-way switches — once on, cannot be turned off. Intentional: prevents
//   accidental destruction of audit-relevant secrets.
// - DNS A-record is created in the privatelink.vaultcore.azure.net zone the
//   caller passes in.

@description('Key Vault name, e.g. tk-com-orderintake-stage-kv. 3-24 chars, globally unique.')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region.')
param location string

@description('Entra tenant ID for RBAC. Defaults to the deployment subscription tenant.')
param tenantId string = subscription().tenantId

@description('Resource ID of the subnet that will host the PE NIC.')
param privateEndpointSubnetId string

@description('Resource ID of the privatelink.vaultcore.azure.net private DNS zone.')
param privateDnsZoneId string

@description('SKU. `standard` covers EOP needs; `premium` only when HSM-backed keys are required.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Whether ARM templates can read secrets at deploy time via @Microsoft.KeyVault inline references. Default false — EOP and similar apps fetch via MSI at runtime, which is the Dep §6.3 path. Set true for apps that legitimately need ARM-time secret resolution.')
param enabledForTemplateDeployment bool = false

@description('Whether VMs can fetch secrets/certs from this vault for disk encryption. Default false — set true only when the vault hosts disk-encryption keys.')
param enabledForDiskEncryption bool = false

@description('Whether the Azure Resource Manager (ARM) can pull secrets from this vault when deploying resources. Default false. Distinct from enabledForTemplateDeployment.')
param enabledForDeployment bool = false

@description('Resource tags.')
param tags object = {}

resource kv 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: skuName
    }
    enableRbacAuthorization: true
    enabledForDeployment: enabledForDeployment
    enabledForTemplateDeployment: enabledForTemplateDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
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
          privateLinkServiceId: kv.id
          groupIds: [
            'vault'
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
        name: 'kv'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output id string = kv.id
output name string = kv.name
output vaultUri string = kv.properties.vaultUri
