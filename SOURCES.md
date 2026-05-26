# Source lineage

Tracks where each module came from and — for QB modules we intentionally did **not** port — why.

## Ported as-is from Teknova Quote Builder (`Quote Builder/infra/`)

Each ported module carries a top-of-file `// Provenance:` comment noting the source path and port date.

| Library module | QB source | Port date | Notes |
|---|---|---|---|
| `modules/app-service-plan.bicep` | `infra/app-service-plan.bicep` | 2026-05-25 | Near-verbatim. SKU allow-list unchanged. |
| `modules/app-service-public.bicep` | `infra/app-service.bicep` | 2026-05-25 | Renamed to make public-ingress explicit (Dep §5.5). Otherwise verbatim. |
| `modules/sql-database.bicep` | `infra/sql-database.bicep` | 2026-05-25 | Added `retentionDays` param (was hard-coded to 7 in QB). |
| `modules/static-web-app.bicep` | `infra/static-web-app.bicep` | 2026-05-25 | Verbatim. |

## NOT ported, with reasons

These modules exist in QB but were rejected during the v0.1.0-pre seed. Consumers needing this functionality should wait for the Phase-3 standards-conforming variants rather than copying the QB version.

### `sql-server.bicep` — REJECTED

**QB shape:** `publicNetworkAccess: 'Enabled'`, an `AllowAllAzureIps` firewall rule, SQL authentication via admin login + password.

**Why rejected:**

- Violates Dep §5.1 — production SQL servers must be PE-only with `publicNetworkAccess: 'Disabled'`.
- Violates Dep §6.1 — no long-lived SQL passwords; access is Entra-only via `azureADOnlyAuthentication: true`.
- The `AllowAllAzureIps` rule defeats network isolation by allowing every Azure tenant's IPs to reach the SQL endpoint.

**Library replacement (EOP Phase 3):** `sql-server-with-pe.bicep` — `publicNetworkAccess: 'Disabled'`, no firewall rules, mandatory AAD admin, `azureADOnlyAuthentication: true`, private endpoint to the hub VNet, DNS A-record into `privatelink.database.windows.net`.

### `key-vault.bicep` — REJECTED

**QB shape:** `existing` keyword only — references a Key Vault that was created out-of-band rather than provisioning one.

**Why rejected:**

- A module library needs a **creator** module, not a reference. Consumers can't import a reference to a vault that doesn't exist yet.
- Even if it were a creator, the QB pattern relies on access policies rather than RBAC (Dep §6.3 mandates `enableRbacAuthorization: true`).

**Library replacement (EOP Phase 3):** `keyvault-with-pe.bicep` — RBAC auth, soft-delete + purge protection, `publicNetworkAccess: 'Disabled'`, private endpoint, DNS A-record into `privatelink.vaultcore.azure.net`.

## Native-to-this-library (no QB equivalent)

These modules don't exist in QB at all. Added in Phase 3 (v1.0.0) alongside the rejected-module replacements.

| Library module | Reason | Added |
|---|---|---|
| `modules/app-service-with-pe.bicep` | Backend APIs accessed via App Gateway (Dep §5.1) need the PE variant, not the public variant. | 2026-05-25, v1.0.0 |
| `modules/service-bus.bicep` | EOP's three-worker pipeline (TS ADR-D-003b) needs topics. `publicNetworkAccess: 'Disabled'`, PE, `disableLocalAuth: true` (no SAS). DLQ alerts are a consumer-side concern — set at subscription scope, not namespace. | 2026-05-25, v1.0.0 |

## Phase 3 fresh-write replacements

The two rejected QB modules got fresh-write replacements in Phase 3 (v1.0.0). Listed here for cross-reference; the rejection rationale above remains the authoritative "why."

| Replacement | Replaces (rejected) | Notes |
|---|---|---|
| `modules/sql-server-with-pe.bicep` | `sql-server.bicep` (QB) | No `administratorLogin` / `administratorLoginPassword` params at all. AAD admin via `administrators` block + child `azureADOnlyAuthentications` resource. PE + DNS A. |
| `modules/keyvault-with-pe.bicep` | `key-vault.bicep` (QB) | Creator, not `existing` reference. `enableRbacAuthorization: true`, soft-delete 90d, purge protection. PE + DNS A. |
