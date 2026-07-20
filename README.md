<p align="center">
  <h1 align="center">App Store Connect MCP Server</h1>
  <p align="center">
    A Model Context Protocol server for the App Store Connect API.<br/>
    Manage apps, builds, TestFlight, reviews, and more — directly from Claude.
  </p>
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.2+-F05138.svg?style=flat&logo=swift&logoColor=white" alt="Swift 6.2+"></a>
  <a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14.0+-000000.svg?style=flat&logo=apple&logoColor=white" alt="macOS 14.0+"></a>
  <a href="https://modelcontextprotocol.io"><img src="https://img.shields.io/badge/MCP-compatible-4A90D9.svg?style=flat" alt="MCP Compatible"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat" alt="MIT License"></a>
  <a href="https://github.com/zelentsov-dev/asc-mcp/actions"><img src="https://github.com/zelentsov-dev/asc-mcp/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  <strong>Works with:</strong><br/>
  <a href="https://claude.ai/code"><img src="https://img.shields.io/badge/Claude_Code-black?style=flat&logo=anthropic&logoColor=white" alt="Claude Code"></a>
  <a href="https://claude.ai/download"><img src="https://img.shields.io/badge/Claude_Desktop-black?style=flat&logo=anthropic&logoColor=white" alt="Claude Desktop"></a>
  <a href="https://code.visualstudio.com"><img src="https://img.shields.io/badge/VS_Code-007ACC?style=flat&logo=visualstudiocode&logoColor=white" alt="VS Code"></a>
  <a href="https://cursor.com"><img src="https://img.shields.io/badge/Cursor-000000?style=flat&logo=cursor&logoColor=white" alt="Cursor"></a>
  <a href="https://windsurf.com"><img src="https://img.shields.io/badge/Windsurf-0066FF?style=flat" alt="Windsurf"></a>
  <a href="https://github.com/openai/codex"><img src="https://img.shields.io/badge/Codex_CLI-412991?style=flat&logo=openai&logoColor=white" alt="Codex CLI"></a>
  <a href="https://ai.google.dev"><img src="https://img.shields.io/badge/Gemini_CLI-4285F4?style=flat&logo=google&logoColor=white" alt="Gemini CLI"></a>
</p>

---

## Overview

**asc-mcp** is a Swift-based MCP server that bridges [Claude](https://claude.ai) (or any MCP-compatible host) with the [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi). It exposes **403 tools** across 31 App Store tool domains + 2 core domains, enabling you to automate your entire iOS/macOS release workflow through natural language.

### Key capabilities

- **Multi-account** — manage multiple App Store Connect teams from a single server
- **Full release pipeline** — create versions, attach builds, submit for review, phased rollout
- **TestFlight automation** — beta groups, testers, build distribution, localized What's New
- **Build management** — track processing, encryption compliance, readiness checks
- **Customer reviews** — list, respond, update, delete responses, aggregate statistics
- **In-app purchases** — CRUD for IAPs, localizations, price points, review screenshots
- **Subscriptions** — subscription CRUD, groups, localizations, prices, availability, offer codes, win-back, intro, and promotional offers
- **Provisioning** — bundle IDs, devices, certificates, profiles, capabilities
- **Marketing** — screenshots, app previews, custom product pages, A/B testing (PPO), promoted purchases
- **Accessibility declarations** — manage App Store accessibility support declarations by device family
- **Webhooks** — manage webhook configurations, inspect delivery diagnostics, verify signatures, parse payloads, and triage events
- **Analytics & Metrics** — sales/financial reports, analytics reports, performance metrics, diagnostics
- **Metadata management** — localized descriptions, keywords, What's New across all locales
- **MCP 2025-11-25 surface** — tool annotations, output schemas for stable tools, structured JSON results, and safe result-size metadata
- **OpenAPI contract tooling** — compare the live 403-tool worker catalog and semantic manifest with Apple's official App Store Connect OpenAPI specification

## Quick Start

```bash
# 1. Install via Mint
brew install mint
mint install zelentsov-dev/asc-mcp@v3.15.0

# 2. Add to Claude Code with env vars (simplest setup)
claude mcp add asc-mcp \
  -e ASC_KEY_ID=XXXXXXXXXX \
  -e ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  -e ASC_PRIVATE_KEY_PATH=/path/to/AuthKey.p8 \
  -- ~/.mint/bin/asc-mcp
```

Or use a JSON config file — see [Configuration](#configuration) below.

## Prerequisites

| Requirement | Version |
|-------------|---------|
| macOS | 14.0+ (Sonoma) |
| Swift | 6.2+ |
| Xcode | 26.0+ or a Swift 6.2 toolchain |
| App Store Connect API Key | [Create one here](https://appstoreconnect.apple.com/access/integrations/api) |

## Installation

### Option A: Mint (recommended)

[Mint](https://github.com/yonaskolb/Mint) is the simplest way to install — one command, no manual cloning.

```bash
# Install Mint (if you don't have it)
brew install mint

# Install asc-mcp from GitHub
mint install zelentsov-dev/asc-mcp@v3.15.0

# Register in Claude Code
claude mcp add asc-mcp -- ~/.mint/bin/asc-mcp
```

To install a specific branch or tag:

```bash
mint install zelentsov-dev/asc-mcp@main      # main branch
mint install zelentsov-dev/asc-mcp@develop    # develop branch
mint install zelentsov-dev/asc-mcp@v3.15.0    # specific tag
```

To update to the latest version:

```bash
mint install zelentsov-dev/asc-mcp@v3.15.0 --force
```

### Option B: Build from Source

```bash
git clone https://github.com/zelentsov-dev/asc-mcp.git
cd asc-mcp
swift build -c release

# Register in Claude Code
claude mcp add asc-mcp -- $(pwd)/.build/release/asc-mcp
```

> [!TIP]
> For convenience, copy the binary to a location in your PATH:
> ```bash
> cp .build/release/asc-mcp /usr/local/bin/asc-mcp
> cp -R .build/release/asc-mcp_asc-mcp.bundle /usr/local/bin/
> ```
> Keep the resource bundle beside the executable; it contains the versioned OpenAPI operation contract used by release checks.

## Configuration

### 1. App Store Connect API Key

1. Go to [App Store Connect → Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/integrations/api)
2. Click **Generate API Key** — select appropriate role (Admin or App Manager recommended)
3. Download the `.p8` private key file (you can only download it once!)
4. Note the **Key ID** and **Issuer ID**

### 2. Companies Configuration

asc-mcp supports three configuration methods (checked in this order):

#### Option A: Environment Variables (recommended for MCP clients)

**Single company** — simplest setup:

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_PRIVATE_KEY_PATH=/path/to/AuthKey.p8
# or pass the key content directly:
# export ASC_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIGT..."
# optional:
# export ASC_COMPANY_NAME="My Company"
# export ASC_VENDOR_NUMBER=YOUR_VENDOR_NUMBER          # for analytics
```

**Multiple companies** — numbered variables:

```bash
export ASC_COMPANY_1_NAME="My Company"
export ASC_COMPANY_1_KEY_ID=XXXXXXXXXX
export ASC_COMPANY_1_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_COMPANY_1_KEY_PATH=/path/to/AuthKey1.p8
export ASC_COMPANY_1_VENDOR_NUMBER=YOUR_VENDOR_NUMBER   # optional, for analytics

export ASC_COMPANY_2_NAME="Client Corp"
export ASC_COMPANY_2_KEY_ID=YYYYYYYYYY
export ASC_COMPANY_2_ISSUER_ID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
export ASC_COMPANY_2_KEY_PATH=/path/to/AuthKey2.p8
```

> Numbering starts at 1. The server scans while `ASC_COMPANY_{N}_KEY_ID` exists.

#### Option B: JSON Config File

Create `~/.config/asc-mcp/companies.json`:

```json
{
  "companies": [
    {
      "id": "my-company",
      "name": "My Company",
      "key_id": "XXXXXXXXXX",
      "issuer_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "key_path": "/Users/you/.keys/AuthKey_XXXXXXXXXX.p8",
      "vendor_number": "YOUR_VENDOR_NUMBER"
    },
    {
      "id": "client-company",
      "name": "Client Corp",
      "key_id": "YYYYYYYYYY",
      "issuer_id": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy",
      "key_path": "/Users/you/.keys/AuthKey_YYYYYYYYYY.p8",
      "vendor_number": "YOUR_VENDOR_NUMBER"
    }
  ]
}
```

> **Note:** `vendor_number` is required for analytics tools (`analytics_sales_report`, `analytics_financial_report`, `analytics_app_summary`). Find it in [App Store Connect → Sales and Trends → Reports](https://appstoreconnect.apple.com/trends/reports).

#### Configuration Priority

The server resolves configuration in this order:

1. `--companies /path/to/companies.json` (CLI argument)
2. Constructor parameter (programmatic)
3. `ASC_MCP_COMPANIES=/path/to/companies.json` (env var pointing to JSON file)
4. Default JSON file paths (`~/.config/asc-mcp/companies.json`, etc.)
5. `ASC_COMPANY_1_KEY_ID` ... (multi-company env vars)
6. `ASC_KEY_ID` + `ASC_ISSUER_ID` (single-company env vars)

### 3. MCP Host Configuration

<details>
<summary><strong>Claude Code (CLI)</strong></summary>

```bash
claude mcp add asc-mcp -- ~/.mint/bin/asc-mcp
```

Or add to `.mcp.json` (project) / `.claude/settings.json` (global) with env vars:

```json
{
  "mcpServers": {
    "asc-mcp": {
      "command": "/path/to/asc-mcp",
      "env": {
        "ASC_KEY_ID": "XXXXXXXXXX",
        "ASC_ISSUER_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "ASC_PRIVATE_KEY_PATH": "/path/to/AuthKey.p8"
      }
    }
  }
}
```

</details>

<details>
<summary><strong>Claude Desktop</strong></summary>

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "asc-mcp": {
      "command": "/path/to/asc-mcp",
      "env": {
        "ASC_KEY_ID": "XXXXXXXXXX",
        "ASC_ISSUER_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "ASC_PRIVATE_KEY_PATH": "/path/to/AuthKey.p8"
      }
    }
  }
}
```

</details>

<details>
<summary><strong>Codex CLI</strong></summary>

Add to `~/.codex/config.toml`:

```toml
[mcp_servers.asc-mcp]
command = "/path/to/asc-mcp"
startup_timeout_sec = 20
tool_timeout_sec = 60
enabled = true
```

Set env vars in your shell or use a wrapper script.

</details>

<details>
<summary><strong>Gemini CLI</strong></summary>

Add to `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "asc-mcp": {
      "command": "/path/to/asc-mcp",
      "timeout": 60000,
      "env": {
        "ASC_KEY_ID": "XXXXXXXXXX",
        "ASC_ISSUER_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "ASC_PRIVATE_KEY_PATH": "/path/to/AuthKey.p8"
      }
    }
  }
}
```

</details>

<details>
<summary><strong>VS Code (Copilot / Continue)</strong></summary>

Add to `.vscode/mcp.json`:

```json
{
  "servers": {
    "asc-mcp": {
      "command": "/path/to/asc-mcp",
      "env": {
        "ASC_KEY_ID": "XXXXXXXXXX",
        "ASC_ISSUER_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "ASC_PRIVATE_KEY_PATH": "/path/to/AuthKey.p8"
      }
    }
  }
}
```

</details>

<details>
<summary><strong>Cursor</strong></summary>

Add to Cursor settings → MCP Servers:

```json
{
  "mcpServers": {
    "asc-mcp": {
      "command": "/path/to/asc-mcp",
      "env": {
        "ASC_KEY_ID": "XXXXXXXXXX",
        "ASC_ISSUER_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "ASC_PRIVATE_KEY_PATH": "/path/to/AuthKey.p8"
      }
    }
  }
}
```

</details>

<details>
<summary><strong>Windsurf</strong></summary>

Add to `~/.codeium/windsurf/mcp_config.json`:

```json
{
  "mcpServers": {
    "asc-mcp": {
      "command": "/path/to/asc-mcp",
      "args": ["--workers", "apps,builds,versions,reviews,beta_groups,iap"],
      "env": {
        "ASC_KEY_ID": "XXXXXXXXXX",
        "ASC_ISSUER_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "ASC_PRIVATE_KEY_PATH": "/path/to/AuthKey.p8"
      }
    }
  }
}
```

> **Note:** Windsurf has a 100-tool limit. The server exposes 403 tools by default, so you must use `--workers` to select a subset. See [Worker Filtering](#worker-filtering) below.

</details>

> [!IMPORTANT]
> If the MCP host doesn't inherit your shell PATH, you may need to specify the full path to the binary and ensure `.p8` key paths are absolute.

### Worker Filtering

The server exposes **403 tools** across 31 App Store tool domains + 2 core domains. Some MCP clients impose a tool limit (e.g., Windsurf caps at 100). Use the 33 `--workers` filter keys to enable only the workers you need:

```bash
# Only load apps, builds, and version lifecycle tools
asc-mcp --workers apps,builds,versions

# App Store release preparation subset (108 tools, including always-on and build sub-workers)
asc-mcp --workers apps,accessibility,builds,export_compliance,versions,beta_app,pre_release,app_info,screenshots

# Monetization focus
asc-mcp --workers apps,iap,subscriptions,pricing,promoted
```

`company` and `auth` workers are **always enabled** regardless of the filter (they provide core multi-account and authentication functionality).

When `builds` is enabled, it automatically includes `build_processing` and `build_beta` sub-workers.

### Read-Only Mode

Use `--read-only` when you want safe inspection without App Store Connect mutations:

```bash
asc-mcp --read-only
asc-mcp --read-only --workers apps,builds,reviews,analytics
```

In this mode, read tools such as `*_list`, `*_get`, `*_search`, `*_status`, `*_verify`, `*_parse`, `*_triage`, `auth_*`, analytics, and metrics remain available. Tools that can create, update, upload, submit, release, delete, revoke, clear, cancel, or otherwise mutate App Store Connect are blocked before their worker handler runs. `company_switch` remains available because it changes only the local active company context.

### OpenAPI Contract and Drift Tooling

Use the operation-contract command to compare the actual credential-free `WorkerManager` catalog with the semantic manifest and the pinned Apple App Store Connect OpenAPI specification. The production manifest records exact Apple `operationId`, HTTP method, path, invocation-scoped input bindings, typed fixed values, response lineage, local workflows, implementation state, deprecated aliases, and deliberately deferred operations. The command does **not** load App Store Connect credentials or start the MCP server.

```bash
rm -rf /tmp/asc-openapi
mkdir -p /tmp/asc-openapi
curl -L --fail -o /tmp/asc-openapi/spec.zip \
  https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip
spec_entry="$(unzip -Z1 /tmp/asc-openapi/spec.zip | grep -E '(^|/)openapi\.oas[^/]*\.json$')"
test "$(echo "$spec_entry" | grep -c .)" -eq 1
unzip -p /tmp/asc-openapi/spec.zip "$spec_entry" > /tmp/asc-openapi/openapi.oas.json

swift run asc-mcp openapi-contract-check \
  --spec /tmp/asc-openapi/openapi.oas.json \
  --json-output /tmp/asc-openapi/operation-contract.json \
  --markdown-output /tmp/asc-openapi/operation-contract.md \
  --strict
```

The manifest is pinned to Apple API 4.4.1 by version, SHA-256, path count, and operation count. It currently maps 375 Apple operations, explicitly defers 525, and scopes out 363, covering all 1,263 operations without overlap. CI fails when the Apple document changes, a mapped operation moves or disappears, a public tool or worker drifts from the manifest, an input field loses its binding, response lineage becomes invalid, or a deferred decision expires. Unexposed optional Apple parameters are warnings so they remain visible in the generated backlog.

Manifest schema v2 also accounts for every optional Apple query and request-body input as publicly bound, internally controlled, intentionally omitted with a reviewed reason, or still unclassified. The checked-in `optionalInputCoveragePin` records the exact current totals and a SHA-256 digest of the sorted input identities and dispositions; `--strict` rejects a missing pin or any count- or identity-level drift. The pin makes phased remediation auditable and regression-safe, but it is not a claim that every optional Apple input is already public. The v3.15.0 pin is 2,265 total: 838 bound, 40 internally controlled, 1,387 intentionally omitted, and 0 unclassified. Its identity SHA-256 is `563eb15f437dc6935ae7ab003eabf68cc24a4c6cae5ad36c197d13e6f0c2c736`.

`--strict` is the merge- and tag-time release gate. Every declared `target` or `broken` tool remains an error in reports, and a regression test pins their exact state. The current baseline has no `target` or `broken` implementations and no implementation drift, so any implementation that leaves `asBuilt`, any structural contract error, or any optional-input coverage drift blocks both merges and releases. `--structural-strict` remains available only for local phased remediation work.

This gate proves operation identity, top-level MCP field ownership, required Apple inputs, typed internal values, and response source/pointer lineage. Full MCP type/enum/range parity and complete typed response schemas remain separate optimization phases; the current mapping status is 395 partial and 8 deprecated.

The older `openapi-coverage` command remains available for the high-level domain report in [`ASC-OPENAPI-COVERAGE-GENERATED.md`](ASC-OPENAPI-COVERAGE-GENERATED.md). The operation contract is the authoritative release gate.

**Available worker names:**

| Worker | Prefix | Tools | Description |
|--------|--------|-------|-------------|
| `company` | `company_` | 3 | Multi-account management |
| `auth` | `auth_` | 4 | JWT token tools |
| `apps` | `apps_` | 9 | App listing, metadata, localizations |
| `accessibility` | `accessibility_` | 6 | App Store accessibility declarations |
| `webhooks` | `webhooks_` | 11 | Webhook notifications, delivery diagnostics, and receiver helpers |
| `xcode_cloud` | `xcode_cloud_` | 30 | Xcode Cloud products, workflows, build runs, artifacts, issues, test results, and SCM |
| `builds` | `builds_` | 4 | Build management |
| `build_processing` | `builds_get_processing_*`, `builds_update_encryption`, `builds_check_readiness` | 4 | Build states, encryption |
| `export_compliance` | `export_compliance_` | 11 | Encryption declarations, document uploads, build linkage, readiness |
| `build_beta` | `builds_*_beta_*`, individual tester build tools | 11 | TestFlight localizations, notifications |
| `versions` | `app_versions_` | 17 | Version lifecycle, age ratings, submit, release |
| `reviews` | `reviews_` | 8 | Customer reviews and responses |
| `beta_groups` | `beta_groups_` | 9 | TestFlight groups |
| `beta_feedback` | `beta_feedback_` | 8 | TestFlight feedback screenshots, crash submissions, crash logs |
| `beta_testers` | `beta_testers_` | 12 | Tester management |
| `iap` | `iap_` | 46 | In-app purchases, pricing, availability, offer codes, review assets |
| `subscriptions` | `subscriptions_` | 73 | Subscription lifecycle, pricing, availability, offers, assets |
| `sandbox` | `sandbox_` | 3 | Sandbox testers |
| `beta_app` | `beta_app_` | 10 | Beta app localizations and review |
| `pre_release` | `pre_release_` | 3 | Pre-release versions |
| `beta_license` | `beta_license_` | 3 | Beta license agreements |
| `provisioning` | `provisioning_` | 17 | Bundle IDs, devices, certificates |
| `app_info` | `app_info_` | 10 | App info, categories, EULA |
| `pricing` | `pricing_` | 9 | Territories, pricing |
| `users` | `users_` | 10 | Team members, roles |
| `app_events` | `app_events_` | 9 | In-app events, localizations |
| `analytics` | `analytics_` | 11 | Sales/financial reports, analytics |
| `screenshots` | `screenshots_` | 16 | Screenshots, previews, sets |
| `custom_pages` | `custom_pages_` | 10 | Custom product pages |
| `ppo` | `ppo_` | 9 | Product page optimization (A/B tests) |
| `promoted` | `promoted_` | 9 | Promoted in-app purchases |
| `review_attachments` | `review_attachments_` | 4 | App Store review attachments |
| `metrics` | `metrics_` | 4 | Performance metrics, diagnostics |

### Token Cost

When connected to an LLM client, tool definitions consume context tokens. Here's the approximate footprint:

| Configuration | Tools | ~Tokens |
|---|---:|---:|
| All workers (default) | 403 | **~45,800** |
| Release workflow: `apps,builds,export_compliance,versions,reviews` | ~71 | ~8,800 |
| Monetization: `apps,iap,subscriptions,pricing` | 144 | ~16,300 |
| TestFlight: `apps,builds,beta_groups,beta_testers` | ~56 | ~6,000 |
| Marketing: `apps,screenshots,custom_pages,ppo,promoted` | ~60 | ~6,800 |
| `--workers apps` | 16 | ~2,000 |

**Heaviest workers:** Subscriptions (73 tools), InAppPurchases (46 tools), Xcode Cloud (30 tools), Provisioning and App Lifecycle (17 tools each).

For 200K-context clients, ~45.8K tokens is about 23% of the window. For clients with smaller context windows, use `--workers` to reduce the footprint.

## Available Tools

**403 tools** organized across 31 App Store tool domains + 2 core domains (use the 33 `--workers` filter keys — see [Worker Filtering](#worker-filtering)):

<details>
<summary><strong>Company Management</strong> — 3 tools</summary>

| Tool | Description |
|------|-------------|
| `company_list` | List all configured companies |
| `company_switch` | Switch active company for API operations |
| `company_current` | Get current active company info |

</details>

<details>
<summary><strong>Authentication</strong> — 4 tools</summary>

| Tool | Description |
|------|-------------|
| `auth_generate_token` | Generate JWT token for API access |
| `auth_validate_token` | Locally validate a standard team-key JWT: ES256 signature, configured `kid`/`iss`, App Store Connect audience, issued-at and expiration claims, and the 20-minute maximum lifetime. This makes no Apple API call and does not prove server acceptance. |
| `auth_refresh_token` | Force refresh JWT token |
| `auth_token_status` | Get JWT token cache status |

</details>

<details>
<summary><strong>Apps Management</strong> — 9 tools</summary>

| Tool | Description |
|------|-------------|
| `apps_list` | List all applications with filtering |
| `apps_get_details` | Get detailed app information |
| `apps_search` | Search apps by name or Bundle ID |
| `apps_list_versions` | List all versions with states |
| `apps_get_metadata` | Get localized metadata for a version |
| `apps_update_metadata` | Update metadata (What's New, description, etc.) |
| `apps_list_localizations` | List localizations with content status |
| `apps_create_localization` | Create a new localization for a version |
| `apps_delete_localization` | Delete a localization from a version |

</details>

<details>
<summary><strong>Accessibility Declarations</strong> — 6 tools</summary>

| Tool | Description |
|------|-------------|
| `accessibility_list` | List accessibility declarations for an app |
| `accessibility_get` | Get one accessibility declaration |
| `accessibility_create` | Create a declaration for a device family |
| `accessibility_update` | Update support flags or publish a declaration |
| `accessibility_delete` | Delete a declaration |
| `accessibility_list_relationships` | List declaration relationship IDs for an app |

</details>

<details>
<summary><strong>Webhook Notifications</strong> — 11 tools</summary>

| Tool | Description |
|------|-------------|
| `webhooks_list` | List webhooks for an app |
| `webhooks_get` | Get a webhook by ID |
| `webhooks_create` | Create a webhook configuration |
| `webhooks_update` | Update webhook fields |
| `webhooks_delete` | Delete a webhook |
| `webhooks_list_deliveries` | List delivery attempts |
| `webhooks_redeliver` | Redeliver an existing delivery |
| `webhooks_ping` | Send a test ping |
| `webhooks_verify_signature` | Verify `x-apple-signature` against the exact raw payload body |
| `webhooks_parse_payload` | Parse and normalize a raw webhook notification payload |
| `webhooks_triage_event` | Produce an actionable triage plan for webhook events or delivery failures |

</details>

<details>
<summary><strong>Xcode Cloud</strong> — 30 tools</summary>

| Tool | Description |
|------|-------------|
| `xcode_cloud_products_list` | List Xcode Cloud products |
| `xcode_cloud_products_get` | Get an Xcode Cloud product |
| `xcode_cloud_product_workflows_list` | List workflows for a product |
| `xcode_cloud_product_build_runs_list` | List build runs for a product |
| `xcode_cloud_workflows_get` | Get a workflow |
| `xcode_cloud_workflow_build_runs_list` | List build runs for a workflow |
| `xcode_cloud_build_runs_get` | Get a build run |
| `xcode_cloud_build_runs_start` | Start or rebuild an Xcode Cloud build |
| `xcode_cloud_build_run_actions_list` | List build actions for a run |
| `xcode_cloud_build_run_builds_list` | List App Store Connect builds created by a run |
| `xcode_cloud_actions_get` | Get a build action |
| `xcode_cloud_action_artifacts_list` | List artifacts for an action |
| `xcode_cloud_action_issues_list` | List issues for an action |
| `xcode_cloud_action_test_results_list` | List test results for an action |
| `xcode_cloud_artifacts_get` | Get an artifact |
| `xcode_cloud_issues_get` | Get an issue |
| `xcode_cloud_test_results_get` | Get a test result |
| `xcode_cloud_xcode_versions_list` | List available Xcode versions |
| `xcode_cloud_xcode_versions_get` | Get an Xcode version |
| `xcode_cloud_macos_versions_list` | List available macOS versions |
| `xcode_cloud_macos_versions_get` | Get a macOS version |
| `xcode_cloud_scm_providers_list` | List SCM providers |
| `xcode_cloud_scm_providers_get` | Get an SCM provider |
| `xcode_cloud_scm_provider_repositories_list` | List repositories for an SCM provider |
| `xcode_cloud_scm_repositories_list` | List SCM repositories |
| `xcode_cloud_scm_repositories_get` | Get an SCM repository |
| `xcode_cloud_scm_repository_git_references_list` | List repository git references |
| `xcode_cloud_scm_repository_pull_requests_list` | List repository pull requests |
| `xcode_cloud_scm_git_references_get` | Get a git reference |
| `xcode_cloud_scm_pull_requests_get` | Get a pull request |

</details>

<details>
<summary><strong>TestFlight Beta Feedback</strong> — 8 tools</summary>

| Tool | Description |
|------|-------------|
| `beta_feedback_list_crashes` | List beta crash feedback submissions |
| `beta_feedback_get_crash` | Get one beta crash feedback submission |
| `beta_feedback_get_crash_log` | Read crash log for a submission |
| `beta_feedback_get_crash_log_by_id` | Read crash log by crash log ID |
| `beta_feedback_delete_crash` | Delete a beta crash feedback submission |
| `beta_feedback_list_screenshots` | List beta screenshot feedback submissions |
| `beta_feedback_get_screenshot` | Get one beta screenshot feedback submission |
| `beta_feedback_delete_screenshot` | Delete a beta screenshot feedback submission |

</details>

<details>
<summary><strong>Builds</strong> — 4 tools</summary>

| Tool | Description |
|------|-------------|
| `builds_list` | List builds with processing states |
| `builds_get` | Get detailed build information |
| `builds_find_by_number` | Find build by version number |
| `builds_list_for_version` | Get builds for specific app version |

</details>

<details>
<summary><strong>Build Processing</strong> — 4 tools</summary>

| Tool | Description |
|------|-------------|
| `builds_get_processing_state` | Get current processing state |
| `builds_update_encryption` | Set encryption compliance |
| `builds_get_processing_status` | Get detailed processing status |
| `builds_check_readiness` | Check if build is ready for submission |

</details>

<details>
<summary><strong>Export Compliance</strong> — 11 tools</summary>

| Tool | Description |
|------|-------------|
| `export_compliance_list_declarations` | List an app's encryption declarations with strict pagination |
| `export_compliance_get_declaration` | Get one declaration without deprecated document URL fields |
| `export_compliance_create_declaration` | Create an encryption declaration questionnaire for an app |
| `export_compliance_create_document` | Reserve, transfer, commit, and poll a document from one immutable local snapshot |
| `export_compliance_get_document` | Get safe delivery metadata without signed URLs, tokens, or upload headers |
| `export_compliance_update_document` | Apply a low-level nullable checksum or uploaded-state patch |
| `export_compliance_upload_document` | Resume an AWAITING_UPLOAD reservation with exact bytes and its lowercase MD5 receipt |
| `export_compliance_inspect_document` | Inspect document presence and classify its delivery state |
| `export_compliance_get_build_declaration` | Get the declaration currently attached to a build |
| `export_compliance_attach_build_declaration` | Attach an approved declaration and verify the relationship |
| `export_compliance_check_release_readiness` | Evaluate only the build's export-compliance release gate |

</details>

<details>
<summary><strong>TestFlight Beta Details</strong> — 11 tools</summary>

| Tool | Description |
|------|-------------|
| `builds_get_beta_detail` | Get TestFlight configuration for build |
| `builds_update_beta_detail` | Update TestFlight settings |
| `builds_set_beta_localization` | Set What's New for TestFlight |
| `builds_list_beta_localizations` | List all TestFlight localizations |
| `builds_get_beta_groups` | Get beta groups for a build |
| `builds_get_beta_testers` | Get individual testers for a build |
| `builds_send_beta_notification` | Send notification to beta testers |
| `builds_add_to_beta_groups` | Add build to beta groups |
| `builds_add_individual_testers` | Add individual testers to a build |
| `builds_remove_individual_testers` | Remove individual testers from a build |
| `builds_list_individual_testers` | List individual testers assigned to a build |

</details>

<details>
<summary><strong>TestFlight Beta Groups</strong> — 9 tools</summary>

| Tool | Description |
|------|-------------|
| `beta_groups_list` | List TestFlight beta groups for an app |
| `beta_groups_create` | Create a new beta group |
| `beta_groups_update` | Update beta group settings |
| `beta_groups_delete` | Delete a beta group |
| `beta_groups_add_testers` | Add testers to a beta group |
| `beta_groups_remove_testers` | Remove testers from a beta group |
| `beta_groups_list_testers` | List testers in a beta group |
| `beta_groups_add_builds` | Add builds to a beta group |
| `beta_groups_remove_builds` | Remove builds from a beta group |

</details>

<details>
<summary><strong>TestFlight Beta Testers</strong> — 12 tools</summary>

Includes tester list/search/get/create/delete, app relationships, invitations, beta group assignment, build assignment, and app removal tools.

</details>

<details>
<summary><strong>App Version Lifecycle</strong> — 17 tools</summary>

| Tool | Description |
|------|-------------|
| `app_versions_create` | Create a new app version |
| `app_versions_list` | List versions with state filtering |
| `app_versions_get` | Get detailed version information |
| `app_versions_get_age_rating_declaration` | Read the App Info age rating questionnaire |
| `app_versions_list_territory_age_ratings` | List calculated age ratings by territory |
| `app_versions_update` | Update version attributes |
| `app_versions_attach_build` | Attach build to version |
| `app_versions_submit_for_review` | Submit for App Store review |
| `app_versions_cancel_review` | Cancel ongoing review |
| `app_versions_release` | Release approved version |
| `app_versions_create_phased_release` | Create gradual rollout |
| `app_versions_get_phased_release` | Get phased release info and ID |
| `app_versions_update_phased_release` | Pause/resume/complete rollout |
| `app_versions_delete_phased_release` | Delete an eligible planned phased release with exact-ID confirmation and unknown-outcome safety |
| `app_versions_set_review_details` | Set reviewer contact info |
| `app_versions_update_age_rating` | Configure age rating declaration |
| `app_versions_delete` | Delete an editable app version with exact-ID confirmation and unknown-outcome safety |

</details>

<details>
<summary><strong>Customer Reviews</strong> — 8 tools</summary>

| Tool | Description |
|------|-------------|
| `reviews_list` | Get reviews with filtering and pagination |
| `reviews_get` | Get specific review details |
| `reviews_list_for_version` | Get reviews for a specific version |
| `reviews_stats` | Aggregated review statistics |
| `reviews_create_response` | Respond to a customer review |
| `reviews_delete_response` | Delete a response |
| `reviews_get_response` | Get response for a review |
| `reviews_summarizations` | Summarize review themes and ratings |

</details>

<details>
<summary><strong>In-App Purchases</strong> — 46 tools</summary>

| Tool | Description |
|------|-------------|
| `iap_list` | List in-app purchases for an app |
| `iap_get` | Get IAP details |
| `iap_create` | Create a new IAP |
| `iap_update` | Update IAP attributes |
| `iap_delete` | Delete an IAP |
| `iap_list_localizations` | List IAP localizations |
| `iap_create_localization` | Create IAP localization |
| `iap_update_localization` | Update IAP localization |
| `iap_delete_localization` | Delete IAP localization |
| `iap_submit_for_review` | Submit IAP for review |
| `iap_list_subscriptions` | List subscription groups |
| `iap_get_subscription_group` | Get subscription group details |
| `iap_inventory` | AI-friendly IAP inventory for an app |
| `iap_list_price_points` | List territory-aware price points |
| `iap_list_price_point_equalizations` | List price point equalizations |
| `iap_get_price_schedule` | Get price schedule |
| `iap_set_price_schedule` | Set price schedule |
| `iap_pricing_summary` | Summarize current and scheduled prices |
| `iap_prepare_offer_prices` | Find price point candidates for offers |
| `iap_set_availability` | Set territory availability |
| `iap_get_availability` | Get availability by IAP or availability ID |
| `iap_list_available_territories` | List available territories |
| `iap_get_promoted_purchase` | Get promoted purchase state |
| `iap_list_offer_codes` | List IAP offer codes |
| `iap_get_offer_code` | Get an IAP offer code |
| `iap_create_offer_code` | Create an IAP offer code |
| `iap_update_offer_code` | Update an IAP offer code |
| `iap_deactivate_offer_code` | Deactivate an IAP offer code |
| `iap_list_offer_code_prices` | List territory-aware offer prices |
| `iap_generate_one_time_codes` | Generate one-time offer codes |
| `iap_list_one_time_codes` | List one-time code batches |
| `iap_get_one_time_code` | Get a one-time code batch |
| `iap_update_one_time_code` | Update a one-time code batch |
| `iap_deactivate_one_time_code` | Deactivate a one-time code batch |
| `iap_get_one_time_code_values` | Get generated one-time code values |
| `iap_create_custom_code` | Create a custom offer code |
| `iap_get_custom_code` | Get custom code details |
| `iap_update_custom_code` | Update a custom code |
| `iap_deactivate_custom_code` | Deactivate a custom code |
| `iap_get_review_screenshot` | Get review screenshot |
| `iap_upload_review_screenshot` | Upload review screenshot |
| `iap_delete_review_screenshot` | Delete review screenshot |
| `iap_upload_image` | Upload promotional image |
| `iap_get_image` | Get promotional image |
| `iap_delete_image` | Delete promotional image |
| `iap_list_images` | List promotional images |

</details>

<details>
<summary><strong>Subscriptions</strong> — 73 tools</summary>

Includes subscription groups, group localizations, subscriptions, subscription localizations, territory-aware prices, price points, price point equalizations, availability, promoted purchase reads, inventory/pricing helpers, intro offers, promotional offers, offer codes, one-time/custom codes, win-back offers, images, and review screenshots. All former public `offer_codes_*`, `intro_offers_*`, `promo_offers_*`, and `winback_*` functionality is exposed through `subscriptions_*`.

The following names remain available for compatibility, but Apple 4.4.1 deprecates their legacy `subscriptionAvailability` resource in favor of plan-type-aware `subscriptionPlanAvailabilities`:

| Tool | Compatibility status |
|------|----------------------|
| `subscriptions_get_availability` | Deprecated legacy availability read |
| `subscriptions_set_availability` | Deprecated legacy availability write |
| `subscriptions_list_available_territories` | Deprecated legacy territory listing |
| `subscriptions_inventory` | Deprecated helper; can omit subscriptions beyond the first included relationship page and is not an authoritative complete inventory |

</details>

<details>
<summary><strong>Sandbox Testers</strong> — 3 tools</summary>

| Tool | Description |
|------|-------------|
| `sandbox_list` | List sandbox testers |
| `sandbox_update` | Update sandbox tester settings |
| `sandbox_clear_purchase_history` | Clear purchase history for sandbox testers |

</details>

<details>
<summary><strong>Beta App</strong> — 10 tools</summary>

| Tool | Description |
|------|-------------|
| `beta_app_list_localizations` | List beta app localizations |
| `beta_app_create_localization` | Create beta app localization |
| `beta_app_get_localization` | Get beta app localization |
| `beta_app_update_localization` | Update beta app localization |
| `beta_app_delete_localization` | Delete beta app localization |
| `beta_app_submit_for_review` | Submit build for beta review |
| `beta_app_list_submissions` | List beta review submissions |
| `beta_app_get_submission` | Get beta review submission |
| `beta_app_get_review_details` | Get beta app review details |
| `beta_app_update_review_details` | Update beta app review details |

</details>

<details>
<summary><strong>Pre-Release Versions</strong> — 3 tools</summary>

Includes pre-release version listing, details, and associated builds.

</details>

<details>
<summary><strong>Beta License Agreements</strong> — 3 tools</summary>

Includes beta license agreement list, get, and update.

</details>

<details>
<summary><strong>Provisioning</strong> — 17 tools</summary>

| Tool | Description |
|------|-------------|
| `provisioning_list_bundle_ids` | List registered bundle identifiers |
| `provisioning_get_bundle_id` | Get bundle ID details |
| `provisioning_create_bundle_id` | Register a new bundle identifier |
| `provisioning_delete_bundle_id` | Delete a bundle identifier |
| `provisioning_list_devices` | List registered devices |
| `provisioning_register_device` | Register a new device (UDID) |
| `provisioning_update_device` | Update device name or status |
| `provisioning_list_certificates` | List signing certificates |
| `provisioning_get_certificate` | Get certificate details |
| `provisioning_revoke_certificate` | Revoke a certificate |
| `provisioning_list_profiles` | List provisioning profiles |
| `provisioning_get_profile` | Get profile details |
| `provisioning_delete_profile` | Delete a profile |
| `provisioning_create_profile` | Create a provisioning profile |
| `provisioning_list_capabilities` | List bundle ID capabilities |
| `provisioning_enable_capability` | Enable a capability |
| `provisioning_disable_capability` | Disable a capability |

</details>

<details>
<summary><strong>App Info</strong> — 10 tools</summary>

Includes app info list/get/update, app info localizations, and EULA get/create/update tools.

</details>

<details>
<summary><strong>Pricing</strong> — 9 tools</summary>

Includes territories, availability, price points, price schedules, and App Store availability v2 tools.

</details>

<details>
<summary><strong>Users</strong> — 10 tools</summary>

Includes team member list/get/update/remove, invitations, visible apps, and visible app relationship updates.

</details>

<details>
<summary><strong>App Events</strong> — 9 tools</summary>

Includes in-app event CRUD plus event localization list/create/update/delete.

</details>

<details>
<summary><strong>Analytics</strong> — 11 tools</summary>

Includes sales, financial, app summary, analytics report request, report, instance, snapshot, and segment tools.

</details>

<details>
<summary><strong>Screenshots & Previews</strong> — 16 tools</summary>

| Tool | Description |
|------|-------------|
| `screenshots_list_sets` | List screenshot sets |
| `screenshots_create_set` | Create a screenshot set |
| `screenshots_delete_set` | Delete a screenshot set |
| `screenshots_list` | List screenshots in a set |
| `screenshots_upload` | Upload a screenshot |
| `screenshots_get` | Get screenshot details |
| `screenshots_delete` | Delete a screenshot |
| `screenshots_reorder` | Reorder screenshots in a set |
| `screenshots_list_preview_sets` | List app preview sets |
| `screenshots_create_preview_set` | Create a preview set |
| `screenshots_delete_preview_set` | Delete a preview set |
| `screenshots_upload_preview` | Upload an app preview |
| `screenshots_get_preview` | Get preview details |
| `screenshots_list_previews` | List previews in a preview set |
| `screenshots_upload_batch` | Upload screenshots in a batch |
| `screenshots_delete_preview` | Delete a preview |

</details>

<details>
<summary><strong>Custom Product Pages</strong> — 10 tools</summary>

| Tool | Description |
|------|-------------|
| `custom_pages_list` | List custom product pages |
| `custom_pages_get` | Get page details |
| `custom_pages_create` | Create a custom page |
| `custom_pages_update` | Update a custom page |
| `custom_pages_delete` | Delete a custom page |
| `custom_pages_list_versions` | List page versions |
| `custom_pages_create_version` | Create a page version |
| `custom_pages_list_localizations` | List version localizations |
| `custom_pages_create_localization` | Create a localization |
| `custom_pages_update_localization` | Update a localization |

</details>

<details>
<summary><strong>Product Page Optimization (A/B Tests)</strong> — 9 tools</summary>

| Tool | Description |
|------|-------------|
| `ppo_list_experiments` | List A/B test experiments |
| `ppo_get_experiment` | Get experiment details |
| `ppo_create_experiment` | Create an experiment |
| `ppo_update_experiment` | Update/start/stop experiment |
| `ppo_delete_experiment` | Delete an experiment |
| `ppo_list_treatments` | List experiment treatments |
| `ppo_create_treatment` | Create a treatment variant |
| `ppo_list_treatment_localizations` | List treatment localizations |
| `ppo_create_treatment_localization` | Create treatment localization |

</details>

<details>
<summary><strong>Promoted Purchases</strong> — 9 tools</summary>

| Tool | Description |
|------|-------------|
| `promoted_list` | List promoted purchases for an app |
| `promoted_get` | Get promotion details |
| `promoted_create` | Create a promotion |
| `promoted_update` | Update promotion (visibility/order) |
| `promoted_delete` | Delete a promotion |
| `promoted_upload_image` | Deprecated: returns migration guidance; Apple removed the endpoint |
| `promoted_get_image` | Deprecated: returns migration guidance; Apple removed the endpoint |
| `promoted_delete_image` | Deprecated: returns migration guidance; Apple removed the endpoint |
| `promoted_get_image_for_purchase` | Deprecated: returns migration guidance; Apple removed the relationship |

</details>

<details>
<summary><strong>Review Attachments</strong> — 4 tools</summary>

Includes App Store review attachment upload, get, delete, and list tools.

</details>

<details>
<summary><strong>Performance Metrics</strong> — 4 tools</summary>

| Tool | Description |
|------|-------------|
| `metrics_app_perf` | Get app performance/power metrics |
| `metrics_build_perf` | Get build performance metrics |
| `metrics_build_diagnostics` | List diagnostics for a build |
| `metrics_get_diagnostic_logs` | Get diagnostic logs |

</details>

## Usage Examples

### Complete Release Workflow

```
You: "Release version 2.2.0 of my app with build 456"

Claude will:
1. app_versions_create(app_id, platform: "IOS", version_string: "2.2.0")
2. app_versions_attach_build(version_id, build_id)
3. app_versions_set_review_details(version_id, contact_email: "...")
4. app_versions_submit_for_review(version_id)
5. app_versions_create_phased_release(version_id)  # after approval
```

### TestFlight Distribution

```
You: "Create a beta group 'External Testers' and distribute the latest build"

Claude will:
1. beta_groups_create(app_id, name: "External Testers")
2. builds_list(app_id, limit: 1)  # find latest
3. builds_set_beta_localization(build_id, locale: "en-US", whats_new: "...")
4. beta_groups_add_testers(group_id, tester_ids: [...])
```

### Review Management

```
You: "Show me all 1-star reviews from the last week and draft responses"

Claude will:
1. reviews_list(app_id, rating: 1, sort: "-createdDate", limit: 50)
2. reviews_create_response(review_id, response_body: "...")  # for each
```

### Multi-Company Workflow

```
You: "Switch to ClientCorp and check their latest build status"

Claude will:
1. company_switch(company: "ClientCorp")
2. apps_list(limit: 5)
3. builds_list(app_id, limit: 1)
4. builds_get_processing_state(build_id)
```

## API Constraints

| Constraint | Details |
|------------|---------|
| **No emojis** | Metadata fields (What's New, Description, Keywords) must not contain emoji characters |
| **Version state** | App Store Connect validates editable states for metadata updates. Rejected and metadata-rejected versions can be edited for resubmission; published or in-review versions may be rejected by Apple. |
| **JWT expiry** | Tokens expire after 20 minutes — the server auto-refreshes them |
| **Rate limits** | Apple enforces per-account rate limits ([documentation](https://developer.apple.com/documentation/appstoreconnectapi/identifying-rate-limits)) |
| **Locale format** | Use standard codes: `en-US`, `ru`, `de-DE`, `ja`, `zh-Hans` |

## Architecture

```
Sources/asc-mcp/
├── EntryPoint.swift                # Entry point, --workers filtering
├── Core/
│   ├── Application.swift           #   MCP server setup & initialization
│   └── ASCError.swift              #   Custom error types
├── Helpers/                        # JSON formatting, pagination, safe helpers
├── Models/                         # API request/response models
│   ├── AppStoreConnect/            #   Apps, versions, localizations
│   ├── Builds/                     #   Builds, beta details, beta groups
│   ├── AppLifecycle/               #   Version lifecycle models
│   ├── InAppPurchases/             #   IAP models
│   ├── Subscriptions/              #   Subscriptions, offer codes, win-back
│   ├── Marketing/                  #   Screenshots, custom pages, PPO, promoted
│   ├── Metrics/                    #   Performance metrics, diagnostics
│   ├── Analytics/                  #   Sales/financial reports
│   ├── Provisioning/               #   Bundle IDs, devices, certificates
│   ├── Shared/                     #   Shared upload/image types
│   └── ...                         #   AppEvents, AppInfo, Pricing, Users
├── Services/
│   ├── HTTPClient.swift            #   Actor-based HTTP with retry logic
│   ├── JWTService.swift            #   ES256 JWT token generation
│   └── CompaniesManager.swift      #   Multi-account management
└── Workers/                        # MCP tool implementations (37 Swift worker classes + MainWorker router)
    ├── MainWorker/WorkerManager    #   Central tool registry & routing
    ├── CompaniesWorker/            #   company_* tools
    ├── AuthWorker/                 #   auth_* tools
    ├── AppsWorker/                 #   apps_* tools
    ├── AccessibilityWorker/        #   accessibility_* tools
    ├── WebhooksWorker/             #   webhooks_* tools
    ├── XcodeCloudWorker/           #   xcode_cloud_* tools
    ├── BuildsWorker/               #   builds_* tools
    ├── BuildProcessingWorker/      #   builds_*_processing tools
    ├── ExportComplianceWorker/     #   export_compliance_* tools
    ├── BuildBetaDetailsWorker/     #   builds_*_beta_* tools
    ├── AppLifecycleWorker/         #   app_versions_* tools
    ├── ReviewsWorker/              #   reviews_* tools
    ├── BetaGroupsWorker/           #   beta_groups_* tools
    ├── BetaFeedbackWorker/         #   beta_feedback_* tools
    ├── BetaTestersWorker/          #   beta_testers_* tools
    ├── InAppPurchasesWorker/       #   iap_* tools
    ├── SubscriptionsWorker/        #   subscriptions_* tools
    ├── OfferCodesWorker/           #   subscriptions offer-code tools
    ├── IntroductoryOffersWorker/   #   subscriptions intro-offer tools
    ├── PromotionalOffersWorker/    #   subscriptions promotional-offer tools
    ├── WinBackOffersWorker/        #   subscriptions win-back tools
    ├── SandboxTestersWorker/       #   sandbox_* tools
    ├── BetaAppWorker/              #   beta_app_* tools
    ├── PreReleaseVersionsWorker/   #   pre_release_* tools
    ├── BetaLicenseAgreementsWorker/ #  beta_license_* tools
    ├── ProvisioningWorker/         #   provisioning_* tools
    ├── AppInfoWorker/              #   app_info_* tools
    ├── PricingWorker/              #   pricing_* tools
    ├── UsersWorker/                #   users_* tools
    ├── AppEventsWorker/            #   app_events_* tools
    ├── AnalyticsWorker/            #   analytics_* tools
    ├── ScreenshotsWorker/          #   screenshots_* tools
    ├── CustomProductPagesWorker/   #   custom_pages_* tools
    ├── ProductPageOptimizationWorker/ # ppo_* tools
    ├── PromotedPurchasesWorker/    #   promoted_* tools
    ├── ReviewAttachmentsWorker/    #   review_attachments_* tools
    └── MetricsWorker/              #   metrics_* tools
```

### Design Principles

- **Swift 6 strict concurrency** — all workers and services are `Sendable`, proper actor isolation
- **Actor-based HTTP client** — thread-safe with exponential backoff and retry logic
- **Prefix-based routing** — `WorkerManager` routes tool calls by name prefix (zero config)
- **Minimal dependencies** — only the [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)

## Troubleshooting

<details>
<summary><strong>Server not responding / MCP disconnection</strong></summary>

1. Verify the binary path is correct in your MCP host config
2. Check that `companies.json` exists and is valid JSON
3. Ensure `.p8` key file paths are absolute and the files exist
4. Try running the binary directly to see error output: `.build/release/asc-mcp`

</details>

<details>
<summary><strong>Authentication errors (401)</strong></summary>

1. Verify your Key ID and Issuer ID match what's shown in App Store Connect
2. Ensure the `.p8` file is the original download (not modified)
3. Check that the API key hasn't been revoked
4. JWT tokens auto-refresh, but if the key is invalid, all requests will fail

</details>

<details>
<summary><strong>Metadata update rejected by App Store Connect state rules</strong></summary>

`apps_update_metadata` sends the metadata PATCH to App Store Connect after local text, locale, and URL validation. Apple decides whether the current version state is editable. Rejected and metadata-rejected versions can be edited and resubmitted; published, in-review, or otherwise locked versions may return an Apple API error.

</details>

<details>
<summary><strong>Build processing takes too long</strong></summary>

Use `builds_get_processing_status` to inspect the current processing state and `builds_check_readiness` to verify App Store/TestFlight readiness. Apple's build processing typically takes 5-30 minutes but can be longer during peak times.

</details>

<details>
<summary><strong>Rate limiting (429 errors)</strong></summary>

The HTTP client automatically retries with exponential backoff on 429 responses. If you consistently hit limits, reduce the frequency of API calls or use pagination with smaller page sizes.

</details>

## Development

### Building

```bash
swift build              # Debug build
swift build -c release   # Release build (optimized)
swift package clean      # Clean build artifacts
```

### Test Mode

```bash
.build/debug/asc-mcp --test    # Runs built-in integration tests
```

### Adding a New Tool

1. Create handler method in the appropriate `Worker+Handlers.swift`
2. Add tool definition in `Worker+ToolDefinitions.swift`
3. Register in worker's `getTools()` method
4. Add routing case in worker's `handleTool()` switch
5. The `WorkerManager` auto-routes by prefix — no changes needed there

### Adding a New Worker

1. Create directory: `Workers/MyWorker/`
2. Create 3 files: `MyWorker.swift`, `MyWorker+ToolDefinitions.swift`, `MyWorker+Handlers.swift`
3. Add worker property and initialization in `WorkerManager.swift`
4. Add routing rule in `WorkerManager.registerWorkers()`
5. Add `getMyTools()` helper method

## Contributing

We welcome contributions! See [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Model Context Protocol](https://modelcontextprotocol.io) — the protocol specification and [Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi) — Apple's official REST API

---

<sub>This is an unofficial, community-maintained tool and is not affiliated with or endorsed by Apple Inc.</sub>
