// Service Bus namespace (Standard) with PE, MSI-only auth, parameterized topics.
//
// Fresh write (no QB lineage; QB has no Service Bus usage). Native to this
// library, added in EOP Phase 3 for the three-worker pipeline (TS ADR-D-003b).
//
// Usage notes:
// - Standard tier — supports topics + subscriptions. Premium reserved for
//   prod throughput escalations (Phase 14 if needed).
// - publicNetworkAccess: 'Disabled'. The PE is the only path.
// - NO SAS authorization rules created. All access is MSI + Entra RBAC.
//   Consumers grant `Azure Service Bus Data Sender` / `Receiver` separately
//   on the namespace or topic scope.
// - Subscriptions are NOT created here. They land with the consumers
//   (Phase 4 intake worker subscribes to inbound; Phase 8 NetSuite writer
//   subscribes to approvals). Creating them in infra would tie subscription
//   lifecycle to infra deploys, which is the wrong shape.

@description('Service Bus namespace name, e.g. tk-com-orderintake-stage-sb. Globally unique.')
param name string

@description('Azure region.')
param location string

@description('Resource ID of the subnet that will host the PE NIC.')
param privateEndpointSubnetId string

@description('Resource ID of the privatelink.servicebus.windows.net private DNS zone.')
param privateDnsZoneId string

@description('Topic names to create. Subscriptions land with the consumer workloads, not here.')
param topicNames array = []

@description('Whether topics require duplicate detection on the MessageId. Default true to match the EOP outbox-pattern use case (consumers dedupe on outbox row Id). Set false for fan-out scenarios where every send is unique.')
param topicRequiresDuplicateDetection bool = true

@description('Duplicate-detection history window when topicRequiresDuplicateDetection is true. ISO-8601 duration. Default PT10M.')
param topicDuplicateDetectionHistoryTimeWindow string = 'PT10M'

@description('Resource tags.')
param tags object = {}

resource sb 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
    zoneRedundant: false
  }
}

resource topics 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = [for topicName in topicNames: {
  parent: sb
  name: topicName
  properties: {
    enablePartitioning: false
    requiresDuplicateDetection: topicRequiresDuplicateDetection
    duplicateDetectionHistoryTimeWindow: topicDuplicateDetectionHistoryTimeWindow
    defaultMessageTimeToLive: 'P14D'
    supportOrdering: false
  }
}]

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
          privateLinkServiceId: sb.id
          groupIds: [
            'namespace'
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
        name: 'sb'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output id string = sb.id
output name string = sb.name
output endpoint string = sb.properties.serviceBusEndpoint
output principalId string = sb.identity.principalId
