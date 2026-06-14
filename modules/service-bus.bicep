// Service Bus namespace (Standard or Premium) with MSI-only auth, parameterized topics.
//
// Fresh write (no QB lineage; QB has no Service Bus usage). Native to this
// library, added in EOP Phase 3 for the three-worker pipeline (TS ADR-D-003b).
//
// Usage notes:
// - `sku`: 'Standard' (default) or 'Premium'. Private endpoints and IP/VNet network
//   rules are PREMIUM-ONLY on Service Bus — a Standard namespace with a PE fails
//   deploy (PrivateEndpointInvalidSku). So the network posture is sku-driven:
//     * Premium → PE created, publicNetworkAccess 'Disabled' (private path only).
//     * Standard → NO PE, publicNetworkAccess 'Enabled' (Standard can't be Disabled
//       without a PE, and can't take network rules). The endpoint is internet-
//       reachable but the DATA PLANE is still locked: disableLocalAuth = true means
//       Entra-RBAC only (no SAS, no anonymous) — only granted principals can use it.
//   Pick Premium where network-path isolation is required; Standard where MSI-only
//   auth on a low-sensitivity / thin-payload bus is acceptable (≈64× cheaper).
// - NO SAS authorization rules created. All access is MSI + Entra RBAC.
//   Consumers grant `Azure Service Bus Data Sender` / `Receiver` separately
//   on the namespace or topic scope.
// - Subscriptions ARE created here, as children of each topic (EOP Phase 10
//   arch-review R6 — reverses the earlier "subscriptions land with consumers"
//   stance). EOP-shaped consumers hold data-plane RBAC only (Sender/Receiver,
//   disableLocalAuth) — no management plane to self-create subscriptions — and
//   nothing in the app calls ServiceBusAdministrationClient. Dev only worked
//   because the Aspire emulator materialized the AppHost topology; in Azure the
//   workers would CreateProcessor against a missing subscription and throw
//   MessagingEntityNotFound. So the topology is declared in infra.

@description('Service Bus namespace name, e.g. tk-com-orderintake-stage-sb. Globally unique.')
param name string

@description('Azure region.')
param location string

@description('Namespace SKU. Premium enables the private endpoint + private-only access; Standard is public-endpoint + MSI-only auth (PE/network-rules are Premium-only on Service Bus).')
@allowed([
  'Standard'
  'Premium'
])
param sku string = 'Standard'

@description('Premium messaging units (1/2/4/8/16). Ignored for Standard.')
@allowed([
  1
  2
  4
  8
  16
])
param messagingUnits int = 1

@description('Resource ID of the subnet that will host the PE NIC. Required only for Premium (PE).')
param privateEndpointSubnetId string = ''

@description('Resource ID of the privatelink.servicebus.windows.net private DNS zone. Required only for Premium (PE).')
param privateDnsZoneId string = ''

@description('Topics to create, each with its subscriptions. Shape: [{ name: string, subscriptions: [{ name: string, lockDuration: string (ISO-8601, e.g. PT5M), maxDeliveryCount: int }] }]. Subscriptions are created in-module (see header note / R6).')
param topics array = []

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
    name: sku
    tier: sku
    capacity: sku == 'Premium' ? messagingUnits : null
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Premium: private-only (PE is the path). Standard: public endpoint (can't be
    // Disabled without a PE, which Standard can't have) — data plane stays MSI-only
    // via disableLocalAuth below.
    publicNetworkAccess: sku == 'Premium' ? 'Disabled' : 'Enabled'
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
    zoneRedundant: false
  }
}

resource topicResources 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = [for topic in topics: {
  parent: sb
  name: topic.name
  properties: {
    enablePartitioning: false
    requiresDuplicateDetection: topicRequiresDuplicateDetection
    duplicateDetectionHistoryTimeWindow: topicDuplicateDetectionHistoryTimeWindow
    defaultMessageTimeToLive: 'P14D'
    supportOrdering: false
  }
}]

// Flatten (topic × subscriptions) into one list so a single resource loop covers
// every subscription across all topics. Subscriptions dead-letter on message
// expiration so the DLQ-depth alert (EOP Step 4) sees expired-but-unconsumed messages.
var subscriptionsByTopic = [for topic in topics: map(topic.subscriptions, sub => {
  topicName: topic.name
  subName: sub.name
  lockDuration: sub.lockDuration
  maxDeliveryCount: sub.maxDeliveryCount
})]
var topicSubscriptions = flatten(subscriptionsByTopic)

resource subscriptionResources 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = [for s in topicSubscriptions: {
  name: '${name}/${s.topicName}/${s.subName}'
  properties: {
    lockDuration: s.lockDuration
    maxDeliveryCount: s.maxDeliveryCount
    deadLetteringOnMessageExpiration: true
    deadLetteringOnFilterEvaluationExceptions: true
  }
  dependsOn: [
    topicResources
  ]
}]

// PE + its DNS zone group exist only for Premium (Service Bus PE is Premium-only).
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = if (sku == 'Premium') {
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

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = if (sku == 'Premium') {
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
