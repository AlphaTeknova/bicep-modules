# alphateknova/bicep-modules — Teknova shared Bicep module library

A library of reusable application-level Bicep modules for Teknova apps. Distinct from [AlphaTeknova/azure-shared-infra](https://github.com/AlphaTeknova/azure-shared-infra), which is a **deployment project** that provisions the hub (VNet, DNS zones, Log Analytics, Bastion). This repo is a **library** that other apps' Bicep imports from.

| Repo | Role | Output |
|---|---|---|
| `AlphaTeknova/azure-shared-infra` | Deployment project | Running hub resources (VNet, DNS, Log Analytics) |
| `alphateknova/bicep-modules` (this repo) | Module library | Reusable `.bicep` building blocks |

## Module catalog (v1.6.0)

The **Deploy-proven** column distinguishes modules with production heritage (have been deployed and run) from those whose first production deploy is still pending. Compile-only modules pass `az bicep build` cleanly but haven't been exercised against live Azure — first deploy may surface API-version, PE-groupId, or RBAC-shape issues that warrant a patch release.

| Module | Purpose | Phase | Deploy-proven |
|---|---|---|---|
| `modules/app-service-plan.bicep` | Linux App Service Plan, parameterized SKU + instance count | Phase 1 (seeded from QB) | ✓ (Quote Builder prod) |
| `modules/app-service-public.bicep` | App Service with **public** ingress — HTTPS-only, MSI, TLS 1.2, Dep §5.5 explicit-exposure naming | Phase 1 (seeded from QB) | ✓ (Quote Builder prod) |
| `modules/app-service-with-pe.bicep` | App Service with PE inbound + VNet integration outbound (default backend shape per Dep §5.1) | Phase 3 (fresh) | Pending (EOP stage deploy is the validation event) |
| `modules/sql-database.bicep` | SQL Database, parameterized SKU + backup redundancy | Phase 1 (seeded from QB) | ✓ (Quote Builder prod) |
| `modules/sql-server-with-pe.bicep` | SQL server with `publicNetworkAccess: 'Disabled'`, AAD-only auth, no firewall, PE + DNS A | Phase 3 (fresh) | Pending |
| `modules/keyvault-with-pe.bicep` | Key Vault with RBAC auth, soft-delete + purge protection, PE + DNS A | Phase 3 (fresh) | Pending |
| `modules/service-bus.bicep` | Service Bus namespace (Standard) with PE, `disableLocalAuth`, parameterized topics + dup-detection | Phase 3 (fresh) | Pending |
| `modules/static-web-app.bicep` | Static Web App resource | Phase 1 (seeded from QB) | ✓ (Quote Builder prod) |
| `modules/front-door-premium.bicep` | Front Door **Premium** + managed WAF — shared edge for internal SPA+API surfaces; Private-Link origins (SWA `staticSites` / App Service `sites`), per-site endpoint+route+custom-domain | Phase 6 (fresh) | Pending (CPQ Workstream 3 stage deploy is the validation event) |

### Adoption guidance for other Teknova apps

- **Deploy-proven modules:** safe to consume now. Migrate at your own pace.
- **Pending modules:** consume if you're willing to be a co-validator and submit fixes/issues against this repo when first deploy turns up problems. Otherwise wait for the `v1.x.y` release notes to mark these "Proven" — that happens after EOP's first successful stage deploy lands.

## Consumer pattern

### Option 1: git submodule (default)

```powershell
# in a consumer repo
git submodule add https://github.com/alphateknova/bicep-modules.git infra/_modules
```

```bicep
// in the consumer's infra/stage.bicep
module asp 'infra/_modules/modules/app-service-plan.bicep' = {
  name: 'asp'
  params: {
    name: 'teknova-orderintake-asp-stage'
    location: location
    sku: 'S1'
    tags: tags
  }
}
```

Submodule pinning gives the consumer a deterministic commit reference and is the simplest setup. Bumping pulls the latest tag with `git submodule update --remote infra/_modules`.

### Option 2: br: ACR reference (future)

When Teknova provisions a shared ACR, modules will be published as Bicep artifacts and consumed via `br:`:

```bicep
module asp 'br:tkshared.azurecr.io/bicep/app-service-plan:v1.0.0' = { ... }
```

That's the proper artifact-store pattern but requires an ACR that doesn't exist yet — revisit when one does.

## Versioning

Git tags per [Dep §10.2]. Format: `vMAJOR.MINOR.PATCH`. Breaking changes (renaming a required parameter, removing an output) bump MAJOR. New optional parameters or new modules bump MINOR. Bug fixes bump PATCH.

Current state:

- `v0.1.0-pre` — initial seeded modules from QB; not standards-conforming for SQL Server / Key Vault / App Service PE variant
- `v1.0.0` — adds the four fresh PE-variant + Service Bus modules; library is standards-conforming end-to-end. **API surface stable; deploy validation of the PE-variant modules pending.**
- `v1.1.0` — hardening pass. Parameterizes opinionated defaults (`service-bus.bicep` dup-detection; `keyvault-with-pe.bicep` template/deployment/disk-encryption flags). Removes a duplicate `vnetRouteAllEnabled` in `app-service-with-pe.bicep`. Adds repo-local CI that lints every module on every PR.
- `v1.2.0`–`v1.4.0` — `app-service*` parameter additions: `appCommandLine` + container warmup limit (v1.2.0); `vnetRouteAllEnabled` + `keyVaultReferenceIdentity` (v1.3.0); `ipSecurityRestrictionsDefaultAction` (v1.4.0). All optional, defaults preserve prior behavior. See git tags.
- `v1.5.0` — adds `front-door-premium.bicep`: shared Front Door **Premium** + managed-WAF edge with Private-Link origins (SWA + App Service). New module → MINOR.
- `v1.6.0` — `static-web-app.bicep`: adds `publicNetworkAccess` (default `Enabled`). Set `Disabled` to lock a SWA behind a Front Door Private-Link origin. Optional param → MINOR.

Expect a `v1.x.y` after EOP's first stage deploy. That release will flip the "Pending" entries in the catalog to "Proven" and call out any parameter/output changes needed by deploy-time findings.

## See also

- [`SOURCES.md`](SOURCES.md) — lineage tracking for each ported module + reasons the rejected QB modules weren't ported
- [`CHANGELOG.md`](CHANGELOG.md) — release notes
