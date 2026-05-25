// Azure SQL Database — one per logical data-sensitivity group.
//
// Provenance: originally Teknova.QuoteBuilder/infra/sql-database.bicep. Ported
// 2026-05-25 as part of EOP Phase 1. SOURCES.md tracks subsequent changes.
//
// This module provisions the database only — schemas and Entra-scoped logins run
// as a post-deploy SQL script (consumers own their init-*.sql).
//
// Default `backupStorageRedundancy` left as `Local` to match QB's safe-cheap stage
// default. Consumers should override to `Geo` for prod via env-driven parameters
// to get cross-region restore.

@description('Database name, e.g. tk-orderintake-stage-sql-db')
param name string

@description('Azure region. Must match parent server.')
param location string

@description('Parent SQL server name (NOT resource ID — module composes the child name).')
param sqlServerName string

@description('Database tier. Basic for stage; Standard or General Purpose Serverless for prod.')
@allowed([
  'Basic'
  'S0'
  'S1'
  'S2'
  'S3'
  'GP_S_Gen5_2'
])
param sku string = 'Basic'

@description('Max database size in bytes. Basic = 2 GB; Standard = 250 GB default.')
param maxSizeBytes int = 2147483648 // 2 GB

@description('Backup storage redundancy. Use Geo for prod (cross-region restore); Local for stage.')
@allowed([
  'Local'
  'Zone'
  'Geo'
  'GeoZone'
])
param backupStorageRedundancy string = 'Local'

@description('PITR retention window in days. 7 is free; up to 35 is paid.')
@minValue(1)
@maxValue(35)
param retentionDays int = 7

@description('Resource tags.')
param tags object = {}

resource sqlDb 'Microsoft.Sql/servers/databases@2024-05-01-preview' = {
  name: '${sqlServerName}/${name}'
  location: location
  tags: tags
  sku: {
    name: sku
    tier: startsWith(sku, 'GP_') ? 'GeneralPurpose' : (sku == 'Basic' ? 'Basic' : 'Standard')
  }
  properties: {
    maxSizeBytes: maxSizeBytes
    requestedBackupStorageRedundancy: backupStorageRedundancy
    zoneRedundant: false
  }
}

resource shortTermRetention 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2024-05-01-preview' = {
  parent: sqlDb
  name: 'default'
  properties: {
    retentionDays: retentionDays
  }
}

output id string = sqlDb.id
output name string = sqlDb.name
