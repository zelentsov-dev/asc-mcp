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

**asc-mcp** is a Swift-based MCP server that bridges [Claude](https://claude.ai) (or any MCP-compatible host) with the [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi). It exposes **265 tools** across 31 workers, enabling you to automate your entire iOS/macOS release workflow through natural language.

### Key capabilities

- **Multi-account** — manage multiple App Store Connect teams from a single server
- **Full release pipeline** — create versions, attach builds, submit for review, phased rollout
- **TestFlight automation** — beta groups, testers, build distribution, localized What's New
- **Build management** — track processing, encryption compliance, readiness checks
- **Customer reviews** — list, respond, update, delete responses, aggregate statistics
- **In-app purchases** — CRUD for IAPs, localizations, price points, review screenshots
- **Subscriptions** — subscription CRUD, groups, localizations, prices, offer codes, win-back offers
- **Provisioning** — bundle IDs, devices, certificates, profiles, capabilities
- **Marketing** — screenshots, app previews, custom product pages, A/B testing (PPO), promoted purchases
- **Analytics & Metrics** — sales/financial reports, analytics reports, performance metrics, diagnostics
- **Metadata management** — localized descriptions, keywords, What's New across all locales

## Quick Start

```bash
# 1. Install via Mint
brew install mint
mint install zelentsov-dev/asc-mcp@1.4.0

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
| Xcode | 16.0+ (for building) |
| App Store Connect API Key | [Create one here](https://appstoreconnect.apple.com/access/integrations/api) |

## Installation

### Option A: Mint (recommended)

[Mint](https://github.com/yonaskolb/Mint) is the simplest way to install — one command, no manual cloning.

```bash
# Install Mint (if you don't have it)
brew install mint

# Install asc-mcp from GitHub
mint install zelentsov-dev/asc-mcp@1.4.0

# Register in Claude Code
claude mcp add asc-mcp -- ~/.mint/bin/asc-mcp
```

To install a specific branch or tag:

```bash
mint install zelentsov-dev/asc-mcp@main      # main branch
mint install zelentsov-dev/asc-mcp@develop    # develop branch
mint install zelentsov-dev/asc-mcp@1.4.0      # specific tag
```

To update to the latest version:

```bash
mint install zelentsov-dev/asc-mcp@1.4.0 --force
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
> ```

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

> **Note:** Windsurf has a 100-tool limit. The server exposes ~109 tools by default, so you must use `--workers` to select a subset. See [Worker Filtering](#worker-filtering) below.

</details>

> [!IMPORTANT]
> If the MCP host doesn't inherit your shell PATH, you may need to specify the full path to the binary and ensure `.p8` key paths are absolute.

### Worker Filtering

The server exposes **265 tools** across 31 workers. Some MCP clients impose a tool limit (e.g., Windsurf caps at 100). Use `--workers` to enable only the workers you need:

```bash
# Only load apps, builds, and version lifecycle tools
asc-mcp --workers apps,builds,versions

# Full release workflow subset (~60 tools, fits within any client limit)
asc-mcp --workers apps,builds,versions,reviews,beta_groups,iap

# Monetization focus
asc-mcp --workers apps,iap,subscriptions,offer_codes,winback,pricing,promoted
```

`company` and `auth` workers are **always enabled** regardless of the filter (they provide core multi-account and authentication functionality).

When `builds` is enabled, it automatically includes `build_processing` and `build_beta` sub-workers.

**Available worker names:**

| Worker | Prefix | Tools | Description |
|--------|--------|-------|-------------|
| `apps` | `apps_` | 9 | App listing, metadata, localizations |
| `builds` | `builds_` | 4 | Build management |
| `build_processing` | `builds_*_processing_` | 4 | Build states, encryption |
| `build_beta` | `builds_*_beta_` | 8 | TestFlight localizations, notifications |
| `versions` | `app_versions_` | 13 | Version lifecycle, submit, release |
| `reviews` | `reviews_` | 7 | Customer reviews and responses |
| `beta_groups` | `beta_groups_` | 9 | TestFlight groups |
| `beta_testers` | `beta_testers_` | 6 | Tester management |
| `iap` | `iap_` | 17 | In-app purchases, prices, review screenshots |
| `subscriptions` | `subscriptions_` | 15 | Subscription CRUD, groups, localizations, prices |
| `offer_codes` | `offer_codes_` | 7 | Subscription offer codes, one-time codes |
| `winback` | `winback_` | 5 | Win-back offers for subscriptions |
| `provisioning` | `provisioning_` | 17 | Bundle IDs, devices, certificates |
| `app_info` | `app_info_` | 7 | App info, categories |
| `pricing` | `pricing_` | 6 | Territories, pricing |
| `users` | `users_` | 7 | Team members, roles |
| `app_events` | `app_events_` | 9 | In-app events, localizations |
| `analytics` | `analytics_` | 11 | Sales/financial reports, analytics |
| `screenshots` | `screenshots_` | 12 | Screenshots, previews, sets |
| `custom_pages` | `custom_pages_` | 10 | Custom product pages |
| `ppo` | `ppo_` | 9 | Product page optimization (A/B tests) |
| `promoted` | `promoted_` | 5 | Promoted in-app purchases |
| `metrics` | `metrics_` | 4 | Performance metrics, diagnostics |

### Token Cost

When connected to an LLM client, tool definitions consume context tokens. Here's the approximate footprint:

| Configuration | Tools | ~Tokens |
|---|---:|---:|
| All workers (default) | 208 | **~24,000** |
| Release workflow: `apps,builds,versions,reviews` | ~40 | ~5,500 |
| Monetization: `apps,iap,subscriptions,pricing` | ~54 | ~6,500 |
| TestFlight: `apps,builds,beta_groups,beta_testers` | ~34 | ~4,500 |
| Marketing: `apps,screenshots,custom_pages,ppo,promoted` | ~46 | ~5,800 |
| `--workers apps` | 16 | ~1,850 |

**Heaviest workers:** Provisioning (17 tools), InAppPurchases (17 tools), Subscriptions (15 tools), AppLifecycle (13 tools), Screenshots (12 tools).

For Claude (200K context) ~22K tokens is ~5–7% — negligible. For clients with smaller context windows, use `--workers` to reduce the footprint.

## Available Tools

**265 tools** organized across 31 workers (use `--workers` to filter — see [Worker Filtering](#worker-filtering)):

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
| `auth_validate_token` | Validate an existing JWT token |
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
<summary><strong>TestFlight Beta Details</strong> — 8 tools</summary>

| Tool | Description |
|------|-------------|
| `builds_get_beta_detail` | Get TestFlight configuration for build |
| `builds_update_beta_detail` | Update TestFlight settings |
| `builds_set_beta_localization` | Set What's New for TestFlight |
| `builds_list_beta_localizations` | List all TestFlight localizations |
| `builds_get_beta_groups` | Get beta groups for a build |
| `builds_get_beta_testers` | Get individual testers for a build |
| `builds_send_beta_notification` | Send notification to beta testers |
| `builds_add_beta_group` | Add build to beta group |

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
<summary><strong>App Version Lifecycle</strong> — 13 tools</summary>

| Tool | Description |
|------|-------------|
| `app_versions_create` | Create a new app version |
| `app_versions_list` | List versions with state filtering |
| `app_versions_get` | Get detailed version information |
| `app_versions_update` | Update version attributes |
| `app_versions_attach_build` | Attach build to version |
| `app_versions_submit_for_review` | Submit for App Store review |
| `app_versions_cancel_review` | Cancel ongoing review |
| `app_versions_release` | Release approved version |
| `app_versions_create_phased_release` | Create gradual rollout |
| `app_versions_get_phased_release` | Get phased release info and ID |
| `app_versions_update_phased_release` | Pause/resume/complete rollout |
| `app_versions_set_review_details` | Set reviewer contact info |
| `app_versions_update_age_rating` | Configure age rating declaration |

</details>

<details>
<summary><strong>Customer Reviews</strong> — 7 tools</summary>

| Tool | Description |
|------|-------------|
| `reviews_list` | Get reviews with filtering and pagination |
| `reviews_get` | Get specific review details |
| `reviews_list_for_version` | Get reviews for a specific version |
| `reviews_stats` | Aggregated review statistics |
| `reviews_create_response` | Respond to a customer review |
| `reviews_delete_response` | Delete a response |
| `reviews_get_response` | Get response for a review |

</details>

<details>
<summary><strong>In-App Purchases</strong> — 17 tools</summary>

| Tool | Description |
|------|-------------|
| `iap_list` | List in-app purchases for an app |
| `iap_get` | Get IAP details |
| `iap_create` | Create a new IAP (consumable, non-consumable, subscription) |
| `iap_update` | Update IAP attributes |
| `iap_delete` | Delete an in-app purchase |
| `iap_list_localizations` | List IAP localizations |
| `iap_create_localization` | Create IAP localization |
| `iap_update_localization` | Update IAP localization |
| `iap_delete_localization` | Delete IAP localization |
| `iap_submit_for_review` | Submit IAP for review |
| `iap_list_subscriptions` | List subscription groups |
| `iap_get_subscription_group` | Get subscription group details |
| `iap_list_price_points` | List available price points |
| `iap_get_price_schedule` | Get price schedule |
| `iap_set_price_schedule` | Set price schedule |
| `iap_get_review_screenshot` | Get review screenshot |
| `iap_create_review_screenshot` | Create review screenshot |

</details>

<details>
<summary><strong>Subscriptions</strong> — 15 tools</summary>

| Tool | Description |
|------|-------------|
| `subscriptions_list` | List subscriptions in a group |
| `subscriptions_get` | Get subscription details |
| `subscriptions_create` | Create a new subscription |
| `subscriptions_update` | Update subscription |
| `subscriptions_delete` | Delete subscription |
| `subscriptions_list_localizations` | List subscription localizations |
| `subscriptions_create_localization` | Create localization |
| `subscriptions_update_localization` | Update localization |
| `subscriptions_delete_localization` | Delete localization |
| `subscriptions_list_prices` | List subscription prices |
| `subscriptions_list_price_points` | List available price points |
| `subscriptions_create_group` | Create subscription group |
| `subscriptions_update_group` | Update subscription group |
| `subscriptions_delete_group` | Delete subscription group |
| `subscriptions_submit` | Submit subscription for review |

</details>

<details>
<summary><strong>Offer Codes</strong> — 7 tools</summary>

| Tool | Description |
|------|-------------|
| `offer_codes_list` | List offer code configurations |
| `offer_codes_create` | Create offer code configuration |
| `offer_codes_update` | Update offer code (enable/disable) |
| `offer_codes_deactivate` | Deactivate all codes |
| `offer_codes_list_prices` | List prices for an offer code |
| `offer_codes_generate_one_time` | Generate one-time use codes (up to 10K) |
| `offer_codes_list_one_time` | List generated one-time codes |

</details>

<details>
<summary><strong>Win-Back Offers</strong> — 5 tools</summary>

| Tool | Description |
|------|-------------|
| `winback_list` | List win-back offers |
| `winback_create` | Create a win-back offer |
| `winback_update` | Update a win-back offer |
| `winback_delete` | Delete a win-back offer |
| `winback_list_prices` | List win-back offer prices |

</details>

<details>
<summary><strong>Introductory Offers</strong> — 4 tools</summary>

| Tool | Description |
|------|-------------|
| `intro_offers_list` | List introductory offers for a subscription |
| `intro_offers_create` | Create an introductory offer |
| `intro_offers_update` | Update an introductory offer (end date only) |
| `intro_offers_delete` | Delete an introductory offer |

</details>

<details>
<summary><strong>Promotional Offers</strong> — 6 tools</summary>

| Tool | Description |
|------|-------------|
| `promo_offers_list` | List promotional offers for a subscription |
| `promo_offers_get` | Get a promotional offer |
| `promo_offers_create` | Create a promotional offer |
| `promo_offers_update` | Update promotional offer prices |
| `promo_offers_delete` | Delete a promotional offer |
| `promo_offers_list_prices` | List prices for a promotional offer |

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
<summary><strong>Screenshots & Previews</strong> — 12 tools</summary>

| Tool | Description |
|------|-------------|
| `screenshots_list_sets` | List screenshot sets |
| `screenshots_create_set` | Create a screenshot set |
| `screenshots_delete_set` | Delete a screenshot set |
| `screenshots_list` | List screenshots in a set |
| `screenshots_create` | Reserve a screenshot upload |
| `screenshots_delete` | Delete a screenshot |
| `screenshots_reorder` | Reorder screenshots in a set |
| `screenshots_list_preview_sets` | List app preview sets |
| `screenshots_create_preview_set` | Create a preview set |
| `screenshots_delete_preview_set` | Delete a preview set |
| `screenshots_create_preview` | Reserve a preview upload |
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
<summary><strong>Promoted Purchases</strong> — 5 tools</summary>

| Tool | Description |
|------|-------------|
| `promoted_list` | List promoted purchases for an app |
| `promoted_get` | Get promotion details |
| `promoted_create` | Create a promotion |
| `promoted_update` | Update promotion (visibility/order) |
| `promoted_delete` | Delete a promotion |

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
You: "Release version 2.1.0 of my app with build 456"

Claude will:
1. app_versions_create(app_id, platform: "IOS", version_string: "2.1.0")
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
| **Version state** | Only versions in `PREPARE_FOR_SUBMISSION` state can be edited |
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
└── Workers/                        # MCP tool implementations (31 workers)
    ├── MainWorker/WorkerManager    #   Central tool registry & routing
    ├── CompaniesWorker/            #   company_* tools
    ├── AuthWorker/                 #   auth_* tools
    ├── AppsWorker/                 #   apps_* tools
    ├── BuildsWorker/               #   builds_* tools
    ├── BuildProcessingWorker/      #   builds_*_processing tools
    ├── BuildBetaDetailsWorker/     #   builds_*_beta_* tools
    ├── AppLifecycleWorker/         #   app_versions_* tools
    ├── ReviewsWorker/              #   reviews_* tools
    ├── BetaGroupsWorker/           #   beta_groups_* tools
    ├── BetaTestersWorker/          #   beta_testers_* tools
    ├── InAppPurchasesWorker/       #   iap_* tools
    ├── SubscriptionsWorker/        #   subscriptions_* tools
    ├── OfferCodesWorker/           #   offer_codes_* tools
    ├── WinBackOffersWorker/        #   winback_* tools
    ├── IntroductoryOffersWorker/   #   intro_offers_* tools
    ├── PromotionalOffersWorker/   #   promo_offers_* tools
    ├── SandboxTestersWorker/      #   sandbox_* tools
    ├── BetaAppWorker/             #   beta_app_* tools
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
<summary><strong>"Version must be in PREPARE_FOR_SUBMISSION state"</strong></summary>

You can only edit metadata for versions that are in `PREPARE_FOR_SUBMISSION` state. Versions in `READY_FOR_SALE`, `IN_REVIEW`, or `WAITING_FOR_REVIEW` are read-only. Create a new version first if needed.

</details>

<details>
<summary><strong>Build processing takes too long</strong></summary>

Use `builds_wait_for_processing` with a reasonable timeout (default 1800s). Apple's build processing typically takes 5–30 minutes but can be longer during peak times.

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
