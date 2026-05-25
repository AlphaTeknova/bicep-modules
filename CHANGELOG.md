# Changelog

Module library releases. Format roughly follows [Keep a Changelog](https://keepachangelog.com/).

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
