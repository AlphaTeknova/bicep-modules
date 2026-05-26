# Changelog

Module library releases. Format roughly follows [Keep a Changelog](https://keepachangelog.com/).

## [v1.1.0] — 2026-05-26

Hardening pass driven by a pre-adoption review across EOP and the candidate next consumer apps. No breaking changes — every new parameter has a default equal to the previous hardcoded value.

### Added

- `modules/service-bus.bicep`: parameters `topicRequiresDuplicateDetection` (default `true`) and `topicDuplicateDetectionHistoryTimeWindow` (default `'PT10M'`). Defaults match v1.0.0 behavior. Consumers with fan-out semantics can opt out.
- `modules/keyvault-with-pe.bicep`: parameters `enabledForTemplateDeployment`, `enabledForDeployment`, `enabledForDiskEncryption` (all default `false`, matching v1.0.0). Consumers who legitimately need ARM-time secret resolution or VM disk-encryption integration can opt in without forking the module.
- `.github/workflows/pr.yml`: repo-local CI lints every `modules/*.bicep` on every PR via `az bicep build`. Closes the gap where the library previously relied on transitive lint via consumer repos.
- `README.md`: catalog now distinguishes deploy-proven modules (Quote Builder prod heritage) from compile-only PE-variant modules (first EOP stage deploy is the validation event). Adoption guidance section added.

### Fixed

- `modules/app-service-with-pe.bicep`: removed duplicate `vnetRouteAllEnabled: true` at the properties level. The canonical location in modern API versions is `siteConfig.vnetRouteAllEnabled`; the properties-level alias is silently accepted by some API versions and ignored by others. Behavior unchanged in practice.

### Versioning notes

`v1.1.0` per the README's MINOR rule: new optional parameters. The dup-removal is technically a generated-template change, but the rendered ARM was redundant — Azure picked one and ignored the other — so no observable consumer behavior changes.

## [v1.0.0] — 2026-05-25

First stable cut. The library is now standards-conforming: SQL Server, Key Vault, App Service, and Service Bus all have PE-only variants. Consumers can compose a full PE-only Azure footprint without falling back to the rejected QB shapes.

### Added

- `modules/sql-server-with-pe.bicep` — Fresh write. `publicNetworkAccess: 'Disabled'`, no firewall rules, no SQL admin login/password, Entra-group AAD admin, `azureADOnlyAuthentication: true`, private endpoint + DNS A in `privatelink.database.windows.net`.
- `modules/keyvault-with-pe.bicep` — Fresh write. `enableRbacAuthorization: true` (no access policies), soft-delete 90d, purge protection on, `publicNetworkAccess: 'Disabled'`, PE + DNS A in `privatelink.vaultcore.azure.net`.
- `modules/app-service-with-pe.bicep` — Fresh write. Linux MSI, VNet integration (outbound), inbound PE + DNS A in `privatelink.azurewebsites.net`, `publicNetworkAccess: 'Disabled'`, diagnostic settings to Log Analytics.
- `modules/service-bus.bicep` — Native. Standard tier, `publicNetworkAccess: 'Disabled'`, `disableLocalAuth: true` (no SAS), parameterized topic list (subscriptions land with consumers, not infra), PE + DNS A in `privatelink.servicebus.windows.net`.

### Versioning

`v1.0.0` because the library is now usable end-to-end for an EOP-shaped app. Future breaking changes (parameter renames, output removals) bump MAJOR per the README's versioning section.

## [v0.1.0-pre] — 2026-05-25

Initial seed. Four modules ported from Teknova Quote Builder `infra/`. Pre-1.0 to signal "library is incomplete" — the standards-conforming SQL Server, Key Vault, App Service PE variant, and Service Bus arrive in EOP Phase 3 before `v1.0.0` is tagged.

### Added

- `modules/app-service-plan.bicep` — Linux App Service Plan, parameterized SKU + instance count. Cloned from QB.
- `modules/app-service-public.bicep` — App Service with public ingress. Cloned from QB's `app-service.bicep`; "-public" suffix added per Dep §5.5 to make the public-exposure decision visible at call sites.
- `modules/sql-database.bicep` — SQL Database with parameterized SKU, max size, backup redundancy, and PITR retention. Cloned from QB. Added `retentionDays` parameter for explicit policy control.
- `modules/static-web-app.bicep` — Static Web App resource. Cloned from QB.

### NOT included (deliberately deferred — see SOURCES.md)

- `sql-server.bicep` from QB — violates Dep §5.1 (`publicNetworkAccess: 'Enabled'`) and Dep §6.1 (SQL admin password). Library version is a **fresh write** in Phase 3 with PE + Entra-only auth.
- `key-vault.bicep` from QB — was an `existing` reference only, not a creator module. Library version is a **fresh write** in Phase 3.

### Coming in v1.0.0 (EOP Phase 3)

- `app-service-with-pe.bicep`
- `sql-server-with-pe.bicep`
- `keyvault-with-pe.bicep`
- `service-bus.bicep`
