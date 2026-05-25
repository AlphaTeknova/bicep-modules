# alphateknova/bicep-modules — Teknova shared Bicep module library

A library of reusable application-level Bicep modules for Teknova apps. Distinct from [AlphaTeknova/azure-shared-infra](https://github.com/AlphaTeknova/azure-shared-infra), which is a **deployment project** that provisions the hub (VNet, DNS zones, Log Analytics, Bastion). This repo is a **library** that other apps' Bicep imports from.

| Repo | Role | Output |
|---|---|---|
| `AlphaTeknova/azure-shared-infra` | Deployment project | Running hub resources (VNet, DNS, Log Analytics) |
| `alphateknova/bicep-modules` (this repo) | Module library | Reusable `.bicep` building blocks |

## Module catalog (v0.1.0-pre)

| Module | Purpose | Phase |
|---|---|---|
| `modules/app-service-plan.bicep` | Linux App Service Plan, parameterized SKU + instance count | Phase 1 (seeded from QB) |
| `modules/app-service-public.bicep` | App Service with **public** ingress — HTTPS-only, MSI, TLS 1.2, Dep §5.5 explicit-exposure naming | Phase 1 (seeded from QB) |
| `modules/sql-database.bicep` | SQL Database, parameterized SKU + backup redundancy | Phase 1 (seeded from QB) |
| `modules/static-web-app.bicep` | Static Web App resource | Phase 1 (seeded from QB) |

Pending modules (added in EOP Phase 3 — see SOURCES.md for why they aren't seeded):

- `app-service-with-pe.bicep` — App Service with private endpoint (the default for backend APIs per Dep §5.1)
- `sql-server-with-pe.bicep` — SQL server with `publicNetworkAccess: 'Disabled'`, Entra-only auth, PE, DNS A-record
- `keyvault-with-pe.bicep` — Key Vault with RBAC auth, soft-delete + purge protection, PE, DNS A-record
- `service-bus.bicep` — Service Bus namespace with PE, DLQ alerts

These four are the standards-conforming primitives; the v1.0.0 cut bundles them with the four seeded modules.

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
- `v1.0.0` (planned, EOP Phase 3) — adds the four pending modules; signals "library is standards-conforming"

## See also

- [`SOURCES.md`](SOURCES.md) — lineage tracking for each ported module + reasons the rejected QB modules weren't ported
- [`CHANGELOG.md`](CHANGELOG.md) — release notes
