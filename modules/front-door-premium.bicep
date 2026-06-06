// Azure Front Door Premium — shared WAF edge for Teknova internal surfaces.
//
// Standards: Dep §5.1 puts user-facing App Services behind a WAF edge with the origin
// reachable only privately. This module is the Front Door realization of that posture.
// The standard names Application Gateway (`-ag`); Front Door is the adopted variant for
// the internal SPA + API pair — native Static Web App Private Link support, lower cost,
// and a global edge. The App-Gateway-vs-Front-Door call is the consumer's (e.g. CPQ
// Workstream 3, which reverses the interim Entra-gated-public posture D15).
//
// Shape: ONE Premium profile (per the one-shared-profile / one-resource-per-type rule)
// fronting N internal "sites". Each site = a custom-domained AFD endpoint whose route
// forwards /* to a single origin reached over an APPROVED Private Link — a Static Web App
// (`staticSites`) or an App Service (`sites`). A profile-wide managed-WAF policy (OWASP
// DRS + bot rules) is associated with every custom domain via one security policy.
//
// Deploy ONCE in the shared hub RG (e.g. tk-shared-prod) and pass every env/app surface
// in `sites`. Adding an app later = append to `sites` and redeploy — no new profile.
//
// OUT OF MODULE SCOPE (ops / cross-RG — see the consumer runbook, e.g. CPQ W3.5):
//   - DNS (zones are shared-infra-owned): the `_dnsauth.<host>` TXT for domain validation
//     (token in the `customDomainValidation` output) and the `<host>` CNAME -> the endpoint
//     hostName (in the `endpointHostNames` output).
//   - Private Endpoint APPROVAL on each origin after first deploy — the origin raises a
//     PENDING shared-private-link request. App Service: `az network private-endpoint-connection
//     approve`. SWA: Portal or `az rest` — the generic command does NOT support
//     `Microsoft.Web/staticSites`.
//   - The origin App Service / SWA themselves (app-service-with-pe / static-web-app modules).

@description('Front Door profile name, e.g. tk-shared-prod-fd. One shared Premium profile per the one-resource-per-type rule. The `-fd` token is the Front Door analogue of the standard `-ag` App Gateway token.')
param name string

@description('Profile location metadata. Front Door is a global resource; leave Global.')
param location string = 'Global'

@description('WAF mode. Prevention blocks matched requests; Detection only logs. Prevention is appropriate for an Entra-gated internal surface (small known audience, low false-positive blast radius).')
@allowed([
  'Prevention'
  'Detection'
])
param wafMode string = 'Prevention'

@description('''Internal surfaces fronted by this profile. One entry per custom-domained surface; each becomes an endpoint + origin-group + Private-Link origin + custom domain + route. Element shape:
{
  key:                   'cpq-stage-spa'          // short DNS/resource-safe slug (lowercase + hyphens); also the AFD endpoint name (globally unique)
  customDomain:          'cpq.teknova-stage.net'  // public host users hit
  originHostName:        'red-water-….azurestaticapps.net' OR 'tk-com-cpq-stage-internal.azurewebsites.net'
  privateLinkResourceId: '/subscriptions/…/staticSites/… OR …/sites/…'
  privateLinkGroupId:    'staticSites'            // SWA = staticSites; App Service = sites
  privateLinkLocation:   'westus2'                // region of the origin resource
}''')
param sites array

@description('Resource ID of the Log Analytics workspace for diagnostic settings. Empty disables diagnostics.')
param logAnalyticsWorkspaceId string = ''

@description('Resource tags.')
param tags object = {}

resource profile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor' // Premium required for Private Link origins + managed WAF rule sets
  }
}

// Managed WAF: OWASP Default Rule Set + Bot Manager. Premium-tier policy to match the profile.
resource waf 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  // WAF policy names must be alphanumeric (no hyphens), <=128 chars.
  name: '${replace(name, '-', '')}waf'
  location: 'Global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
        }
      ]
    }
  }
}

// One endpoint per site (the route + custom domain live on it).
resource endpoints 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = [for site in sites: {
  parent: profile
  name: site.key
  location: location
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}]

resource originGroups 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = [for site in sites: {
  parent: profile
  name: '${site.key}-og'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
  }
}]

// The Private-Link origin. Provisioning raises a PENDING PE connection on the target
// (SWA/App Service) that an operator must APPROVE before traffic flows (W3.5).
resource origins 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = [for (site, i) in sites: {
  parent: originGroups[i]
  name: '${site.key}-origin'
  properties: {
    hostName: site.originHostName
    originHostHeader: site.originHostName
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
    sharedPrivateLinkResource: {
      privateLink: {
        id: site.privateLinkResourceId
      }
      privateLinkLocation: site.privateLinkLocation
      groupId: site.privateLinkGroupId
      requestMessage: 'Front Door (${name}) origin for ${site.key}'
    }
  }
}]

// AFD-managed cert per custom domain. Issuance needs the _dnsauth TXT validation
// (token in the customDomainValidation output) placed in DNS out-of-band.
resource customDomains 'Microsoft.Cdn/profiles/customDomains@2023-05-01' = [for site in sites: {
  parent: profile
  name: replace(site.customDomain, '.', '-')
  properties: {
    hostName: site.customDomain
    tlsSettings: {
      certificateType: 'ManagedCertificate'
      minimumTlsVersion: 'TLS12'
    }
  }
}]

resource routes 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = [for (site, i) in sites: {
  parent: endpoints[i]
  name: '${site.key}-route'
  properties: {
    customDomains: [
      {
        id: customDomains[i].id
      }
    ]
    originGroup: {
      id: originGroups[i].id
    }
    supportedProtocols: [
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    httpsRedirect: 'Enabled'
    linkToDefaultDomain: 'Disabled' // serve only on the custom domain, not the *.azurefd.net default
    enabledState: 'Enabled'
  }
  dependsOn: [
    origins[i] // the origin must exist before the route binds its origin group
  ]
}]

// Associate the WAF with every custom domain in one security policy.
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = {
  parent: profile
  name: '${replace(name, '-', '')}wafassoc'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: waf.id
      }
      associations: [
        {
          domains: [for (site, i) in sites: {
            id: customDomains[i].id
          }]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: '${name}-diag'
  scope: profile
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'FrontDoorAccessLog'
        enabled: true
      }
      {
        category: 'FrontDoorHealthProbeLog'
        enabled: true
      }
      {
        category: 'FrontDoorWebApplicationFirewallLog'
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

output profileId string = profile.id
output profileName string = profile.name
output wafPolicyId string = waf.id

@description('Per-site AFD endpoint hostname — CNAME each customDomain to its endpoint.')
output endpointHostNames array = [for (site, i) in sites: {
  key: site.key
  customDomain: site.customDomain
  endpoint: endpoints[i].properties.hostName
}]

@description('Per-site domain-validation token — publish as DNS TXT `_dnsauth.<customDomain>` so the AFD managed cert can issue.')
output customDomainValidation array = [for (site, i) in sites: {
  key: site.key
  host: site.customDomain
  validationToken: customDomains[i].properties.validationProperties.validationToken
}]
