# Changelog

Module library releases. Format roughly follows [Keep a Changelog](https://keepachangelog.com/).

## [v1.3.0] — 2026-05-31

Driven by CPQ Phase 3a prod stand-up — two App Service knobs that had to be set out-of-band via `az` after the first prod apply (and that caused a multi-hour debug of PublicApi failing to boot). Baking them into the modules so the first apply gets the right shape. No breaking changes — both new parameters default to the prior behavior.

### Added

- `modules/app-service-public.bicep`: parameters `vnetRouteAllEnabled` (default `false`) and `keyVaultReferenceIdentity` (default `''`).
  - `vnetRouteAllEnabled` maps to `siteConfig.vnetRouteAllEnabled`. Default `false` = no change for public apps without VNet integration. Set `true` when the app integrates a VNet and must reach private endpoints (KV/SQL). CPQ Phase 3a shipped PublicApi with this `false`; outbound to `*.vault.azure.net` resolved to the blocked public IP and `AddAzureKeyVault` hung at startup → container start-timeout loop. (`app-service-with-pe` already hardcodes `true`.)
  - `keyVaultReferenceIdentity` maps to `properties.keyVaultReferenceIdentity` (omitted when empty → platform default of system-assigned). Set to a UAMI resource ID when the app carries a user-assigned identity AND uses `keyVaultReferences`: platform KV-reference resolution defaults to the system-assigned MI, which typically has no KV RBAC (only the UAMI gets Secrets User), leaving references unresolved (red X). CPQ Phase 3a hit this on the Canary token reference on both apps.
- `modules/app-service-with-pe.bicep`: parameter `keyVaultReferenceIdentity` (same shape, same rationale). It already set `vnetRouteAllEnabled: true`, so no route-all param needed here.

### Versioning notes

`v1.3.0` per the README's MINOR rule: new optional parameters with defaults matching prior behavior (`vnetRouteAllEnabled: false`, `keyVaultReferenceIdentity: ''` → system-assigned). No consumer redeploys forced; EOP's existing usage is unaffected.

### Notes for consumers

- Any app that (a) attaches a user-assigned identity and (b) uses `keyVaultReferences` should set `keyVaultReferenceIdentity` to that UAMI's resource ID, or its KV references will silently fail to resolve.
- Public apps that integrate a VNet to reach private endpoints must set `vnetRouteAllEnabled: true` — VNet integration alone doesn't push outbound DNS/traffic through the integration reliably without it.

## [v1.2.0] — 2026-05-28

Driven by CPQ Phase 2 cleanup item 2c.2 — two App Service warmup knobs that previously had to be set out-of-band via `az webapp config` after every Bicep apply. Baking them into the modules so the first apply gets the right shape and there's no drift between IaC state and runtime state. No breaking changes — every new parameter has a default equal to either Azure's platform default or the empirically-tested CPQ value.

### Added

- `modules/app-service-public.bicep`: parameters `appCommandLine` (default `''`) and `containerStartTimeLimitSeconds` (default `600`, `@minValue(60)`, `@maxValue(1800)`).
  - `appCommandLine` maps to `siteConfig.appCommandLine`. Empty leaves Oryx auto-detection in place; setting it (e.g. `dotnet Teknova.SomeApp.dll`) skips Oryx detection entirely. CPQ found Oryx unreliable inside the warmup probe budget for renamed assemblies — see [feedback_project_rename_runtime_config](https://github.com/AlphaTeknova/CPQ) memory.
  - `containerStartTimeLimitSeconds` is emitted as the `WEBSITES_CONTAINER_START_TIME_LIMIT` app setting (Azure's actual contract — there's no siteConfig field for this). Default `600` matches what CPQ Phase 2 found necessary on B1 SKU; Azure's platform default of 230s busts cert rehash + Oryx detect.
- `modules/app-service-with-pe.bicep`: same two parameters with the same shape. Consumers can use either module without API drift between them.

### Versioning notes

`v1.2.0` per the README's MINOR rule: new optional parameters with default values matching either Azure's defaults (`appCommandLine: ''` = Oryx) or the previously-required-out-of-band value (`WEBSITES_CONTAINER_START_TIME_LIMIT: 600`). No consumer redeploys are forced; consumers who currently set `WEBSITES_CONTAINER_START_TIME_LIMIT` in their `appSettings` param will see the module's default take precedence via the `union()` ordering, but the value lands at `600` either way for current consumers.

### Notes for consumers

- After upgrading to `v1.2.0`, you can drop any out-of-band `az webapp config set --startup-file ...` or `az webapp config appsettings set --name WEBSITES_CONTAINER_START_TIME_LIMIT ...` calls in operator runbooks. The module is now the source of truth.
- If you previously set `WEBSITES_CONTAINER_START_TIME_LIMIT` via the `appSettings` parameter, remove it — the module sets it from `containerStartTimeLimitSeconds` and `union()` resolution may give the module's value precedence depending on dictionary ordering.

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
