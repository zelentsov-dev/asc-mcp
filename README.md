<p align="center">
  <h1 align="center">App Store Connect MCP Server</h1>
  <p align="center">
    A local Model Context Protocol server for the App Store Connect API.<br/>
    Manage apps, builds, TestFlight, reviews, and more from Codex, Claude, and other MCP clients on macOS.
  </p>
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.2+-F05138.svg?style=flat&logo=swift&logoColor=white" alt="Swift 6.2+"></a>
  <a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/macOS_15-CI_tested-000000.svg?style=flat&logo=apple&logoColor=white" alt="macOS 15 CI tested"></a>
  <a href="https://modelcontextprotocol.io"><img src="https://img.shields.io/badge/MCP-compatible-4A90D9.svg?style=flat" alt="MCP Compatible"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat" alt="MIT License"></a>
  <a href="https://github.com/zelentsov-dev/asc-mcp/actions"><img src="https://github.com/zelentsov-dev/asc-mcp/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

---

## Overview

**asc-mcp** is a Swift-based MCP server that connects a local macOS MCP client to the [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi). It exposes **502 tools** across 33 App Store tool domains + 2 core domains, enabling you to automate iOS and macOS release workflows through natural language.

Configuration examples are included for Codex, Claude Code, Claude Desktop, Gemini CLI, VS Code with GitHub Copilot, Continue, Cursor, and Devin Desktop (formerly Windsurf). Client configuration is documented; release CI verifies installation, MCP initialization, and tool discovery on macOS rather than launching every third-party client.

New here? Follow the [Quick Start](#quick-start). The remaining sections are reference material for advanced configuration, tool selection, and contributors.

### Key capabilities

- **Release and metadata** — versions, localizations, builds, review submissions, phased rollout, and Xcode Cloud
- **TestFlight and uploads** — beta groups, testers, feedback, recruitment, build delivery, processing, and export compliance
- **Monetization** — in-app purchases, subscriptions, pricing, availability, offer codes, and promotional offers
- **Marketing** — screenshots, previews, custom product pages, product page optimization, and promoted purchases
- **Accounts and provisioning** — multiple App Store Connect teams, users, bundle IDs, devices, certificates, profiles, and capabilities
- **Feedback and operations** — customer reviews, webhooks, accessibility declarations, analytics, metrics, and diagnostics
- **Safer automation** — read-only mode, confirmation safeguards, strict pagination, and mutation recovery guidance
- **Auditable API coverage** — a versioned Apple OpenAPI contract and release-time drift checks

## Platform Support

`asc-mcp` is a local `stdio` server: the MCP client starts it on the same computer. A client being available on Linux or Windows does not make this Swift server cross-platform.

| Environment | Status | Notes |
|---|---|---|
| macOS 15.6+ with Xcode 26.x | **Recommended** | Release CI specifically uses GitHub's macOS 15 runner with Xcode 26.2 |
| macOS 14.0-15.5 | Declared deployment target only | Build and runtime are unverified; a separately installed Swift 6.2+ toolchain may be needed |
| Linux | Not supported yet | Porting work and Linux CI are not complete |
| Windows | Not supported | Current source dependencies and Swift MCP `stdio` transport are not Windows-compatible |

See [Apple's Xcode system requirements](https://developer.apple.com/support/xcode/) for the macOS versions supported by each Xcode release.

Web and cloud sessions do not automatically inherit a local MCP configuration. Run the MCP client locally on a compatible Mac, or use a client feature that explicitly keeps execution on that Mac.

## Quick Start

The recommended setup stores App Store Connect credentials once in a private local file. MCP clients then need only the path to the `asc-mcp` executable.

### 1. Install asc-mcp

```bash
brew install mint
mint install zelentsov-dev/asc-mcp@v4.1.3
~/.mint/bin/asc-mcp --version
```

### 2. Create an App Store Connect API key

1. Open [App Store Connect → Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/integrations/api).
2. Generate a key with the least-privileged role that covers your workflow. App Manager or Admin is needed only when the corresponding operations require it.
3. Download the `.p8` file. Apple allows it to be downloaded only once.
4. Copy the Key ID and Issuer ID.

### 3. Save the credentials locally

Create private configuration directories, then move the downloaded `.p8` file into `~/.keys/`. Replace the source path and filename in the second command:

```bash
mkdir -p ~/.config/asc-mcp ~/.keys
chmod 700 ~/.config/asc-mcp ~/.keys
mv /path/to/downloaded/AuthKey_XXXXXXXXXX.p8 ~/.keys/
```

Create `~/.config/asc-mcp/companies.json`:

```json
{
  "companies": [
    {
      "id": "my-company",
      "name": "My Company",
      "key_id": "XXXXXXXXXX",
      "issuer_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "key_path": "/Users/you/.keys/AuthKey_XXXXXXXXXX.p8"
    }
  ]
}
```

Replace `/Users/you` with your actual home-directory path. Keep both files outside the repository and restrict access:

```bash
chmod 600 ~/.config/asc-mcp/companies.json
chmod 600 /Users/you/.keys/AuthKey_XXXXXXXXXX.p8
```

> [!CAUTION]
> Never commit `companies.json`, a `.p8` key, or raw credentials to Git. Revoke the App Store Connect key immediately if it is exposed.

### 4. Connect your MCP client

Choose one client. You do not need to configure every client.

**Codex**

```bash
codex mcp add asc-mcp -- ~/.mint/bin/asc-mcp
codex mcp list
```

**Claude Code**

```bash
claude mcp add \
  --transport stdio \
  --scope user \
  asc-mcp \
  -- ~/.mint/bin/asc-mcp

claude mcp get asc-mcp
claude mcp list
```

For Claude Desktop, Gemini CLI, VS Code, Continue, Cursor, and Devin Desktop, use the ready-to-copy examples in [MCP Client Setup](#mcp-client-setup).

### 5. Try it

Restart a GUI client after changing its configuration, open its MCP tool list, and ask:

```text
List my App Store Connect apps.
```

If the connection or request fails, see [Troubleshooting](#troubleshooting).

## Installation

### Mint on macOS (recommended)

[Mint](https://github.com/yonaskolb/Mint) installs the pinned release from source and keeps the executable at `~/.mint/bin/asc-mcp`.

```bash
brew install mint
mint install zelentsov-dev/asc-mcp@v4.1.3
```

Update or reinstall the pinned release:

```bash
mint install zelentsov-dev/asc-mcp@v4.1.3 --force
```

Stable users should install a version tag. Installing `main` or `develop` is intended only for maintainers and pre-release testing.

### Build from source

Use Xcode 26.x on a compatible macOS version, or install a standalone Swift 6.2+ toolchain.

```bash
git clone https://github.com/zelentsov-dev/asc-mcp.git
cd asc-mcp
swift build -c release
```

The executable is `.build/release/asc-mcp`. If you copy it elsewhere, also copy the adjacent resource bundle:

```bash
cp .build/release/asc-mcp /usr/local/bin/asc-mcp
cp -R .build/release/asc-mcp_asc-mcp.bundle /usr/local/bin/
```

The bundle contains the versioned OpenAPI operation contract used by release checks.

### Upgrading from an older release

<details>
<summary><strong>From v4.0.x</strong></summary>

Version 4.1 keeps every existing tool name, required input, projection key, and array shape. Xcode Cloud read tools now reject undocumented arguments and validate returned links, paging, relationship lineage, and included resources more strictly. New `*Present` projection fields distinguish Apple-omitted arrays from present empty arrays while legacy array fields remain arrays. Newly exposed nested `*_limit` inputs must be paired with their matching `include` value, and continuation calls must repeat the original request scope unchanged. The new product and workflow delete tools default to a safe preview and require the latest preview receipt plus exact inventory confirmation before permanent deletion.

</details>

<details>
<summary><strong>From v3.18.x</strong></summary>

Version 4 keeps every existing tool name and worker filter, but destructive Marketing and review-attachment calls now require an exact confirmation ID before any Apple request:

| Existing tool | New required confirmation |
|---|---|
| `custom_pages_delete` | `confirm_page_id` |
| `ppo_delete_experiment` | `confirm_experiment_id` |
| `promoted_delete` | `confirm_promoted_purchase_id` |
| `review_attachments_delete` | `confirm_attachment_id` |
| `screenshots_delete_set`, `screenshots_delete_preview_set` | `confirm_set_id` |
| `screenshots_delete` | `confirm_screenshot_id` |
| `screenshots_delete_preview` | `confirm_preview_id` |

`ppo_update_experiment` also requires `confirm_experiment_id` when `state` is supplied. Calls that update only name or traffic proportion remain unchanged. After an `unknown` or `committed_unverified` mutation result, use the returned inspection action before retrying.

Remove undocumented top-level arguments from existing Marketing and review-attachment calls. Version 4 rejects unknown keys before any network request instead of silently ignoring them.

</details>

## Configuration

### Credentials

The default `~/.config/asc-mcp/companies.json` file shown in the Quick Start is recommended because it works consistently for terminal and GUI clients without duplicating secrets in every client configuration.

For multiple companies, add more entries:

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
      "name": "Client Company",
      "key_id": "YYYYYYYYYY",
      "issuer_id": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy",
      "key_path": "/Users/you/.keys/AuthKey_YYYYYYYYYY.p8"
    }
  ]
}
```

`vendor_number` is required only for `analytics_sales_report`, `analytics_financial_report`, and `analytics_app_summary`. Find it in [App Store Connect → Sales and Trends → Reports](https://appstoreconnect.apple.com/trends/reports).

<details>
<summary><strong>Environment-variable alternative</strong></summary>

Environment variables are useful for automation, but GUI apps launched from Finder may not inherit your shell environment. The file-based setup above is simpler for most users.

Single company:

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_PRIVATE_KEY_PATH=/Users/you/.keys/AuthKey_XXXXXXXXXX.p8
export ASC_COMPANY_NAME="My Company"                 # optional
export ASC_VENDOR_NUMBER=YOUR_VENDOR_NUMBER          # optional, analytics only
```

Multiple companies:

```bash
export ASC_COMPANY_1_NAME="My Company"
export ASC_COMPANY_1_KEY_ID=XXXXXXXXXX
export ASC_COMPANY_1_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_COMPANY_1_KEY_PATH=/Users/you/.keys/AuthKey_XXXXXXXXXX.p8

export ASC_COMPANY_2_NAME="Client Company"
export ASC_COMPANY_2_KEY_ID=YYYYYYYYYY
export ASC_COMPANY_2_ISSUER_ID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
export ASC_COMPANY_2_KEY_PATH=/Users/you/.keys/AuthKey_YYYYYYYYYY.p8
```

Numbering starts at 1. Each consecutive entry must provide both `ASC_COMPANY_{N}_KEY_ID` and `ASC_COMPANY_{N}_ISSUER_ID`; scanning stops at the first missing pair.

</details>

<details>
<summary><strong>Configuration resolution order</strong></summary>

The server resolves credentials in this order:

1. `--companies /absolute/path/to/companies.json`
2. Constructor parameter for programmatic embedding
3. `ASC_MCP_COMPANIES=/absolute/path/to/companies.json`
4. Default configuration file locations, including `~/.config/asc-mcp/companies.json`
5. `ASC_COMPANY_1_KEY_ID` and the other numbered multi-company variables
6. `ASC_KEY_ID`, `ASC_ISSUER_ID`, and a private-key variable for one company

</details>

## MCP Client Setup

All examples below assume a Mint installation and the recommended `companies.json` credential file. Replace `/Users/you` with your actual home-directory path. GUI clients generally require an absolute executable path.

| Client | Configuration scope | Notes |
|---|---|---|
| Codex | User config by CLI; optional trusted-project config | Shared by local Codex clients on the same Mac |
| Claude Code | `user`, `local`, or `project` scope | `user` is simplest for a personal App Store utility |
| Claude Desktop | User-level desktop config | Restart after editing |
| Gemini CLI | User settings | Local `stdio` server |
| VS Code with GitHub Copilot | User profile or `.vscode/mcp.json` | Confirm server trust on first start |
| Continue | Workspace `.continue/mcpServers/` | Separate from native VS Code MCP configuration |
| Cursor | User or project `mcp.json` | Use an absolute command path |
| Devin Desktop (formerly Windsurf) | User MCP config | Keep no more than 100 active tools |

<details>
<summary><strong>Codex CLI, IDE extension, and desktop client</strong></summary>

Recommended CLI registration:

```bash
codex mcp add asc-mcp -- ~/.mint/bin/asc-mcp
codex mcp list
codex mcp get asc-mcp --json
```

The same local MCP configuration is shared by Codex clients on that Mac. The user configuration is `$CODEX_HOME/config.toml`, which defaults to `~/.codex/config.toml`:

```toml
[mcp_servers.asc-mcp]
command = "/Users/you/.mint/bin/asc-mcp"
startup_timeout_sec = 20
tool_timeout_sec = 60
enabled = true
```

For a project-specific setup, place the same table in `.codex/config.toml`; Codex loads project configuration only after the project is trusted. If you use shell credentials instead of `companies.json`, explicitly forward them:

```toml
env_vars = ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_PATH"]
```

Restart a GUI client after changing the configuration, then use its MCP view or `/mcp` to confirm that `asc-mcp` is active. See the [official Codex MCP documentation](https://developers.openai.com/codex/mcp/).

</details>

<details>
<summary><strong>Claude Code</strong></summary>

Register once for all local projects:

```bash
claude mcp add \
  --transport stdio \
  --scope user \
  asc-mcp \
  -- ~/.mint/bin/asc-mcp

claude mcp get asc-mcp
claude mcp list
```

Use `--scope local` for only the current project or `--scope project` to create a shared `.mcp.json`. Project servers require trust approval. Never place raw App Store Connect credentials in a committed `.mcp.json`.

Claude stores `user` and `local` MCP entries in `~/.claude.json`; `.claude/settings.json` is not the global MCP registry. Use `/mcp` inside Claude Code to inspect or reconnect the server. See the [official Claude Code MCP documentation](https://code.claude.com/docs/en/mcp).

</details>

<details>
<summary><strong>Claude Desktop</strong></summary>

Add the server to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "asc-mcp": {
      "command": "/Users/you/.mint/bin/asc-mcp"
    }
  }
}
```

Quit and reopen Claude Desktop after saving the file.

</details>

<details>
<summary><strong>Gemini CLI</strong></summary>

Add the server to `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "asc-mcp": {
      "command": "/Users/you/.mint/bin/asc-mcp"
    }
  }
}
```

The default Gemini MCP timeout is intentionally retained. See the [official Gemini CLI MCP documentation](https://google-gemini.github.io/gemini-cli/docs/tools/mcp-server.html).

</details>

<details>
<summary><strong>VS Code with GitHub Copilot</strong></summary>

Run **MCP: Add Server** from the Command Palette and choose the user profile for a personal setup. For a workspace setup, create `.vscode/mcp.json`:

```json
{
  "servers": {
    "asc-mcp": {
      "type": "stdio",
      "command": "/Users/you/.mint/bin/asc-mcp"
    }
  }
}
```

Confirm that you trust the local server when VS Code first starts it. Do not commit user-specific paths or secrets in a shared workspace file. See the [official VS Code MCP documentation](https://code.visualstudio.com/docs/agent-customization/mcp-servers).

</details>

<details>
<summary><strong>Continue</strong></summary>

Continue does not use `.vscode/mcp.json`. Create `.continue/mcpServers/asc-mcp.json` in the workspace:

```json
{
  "mcpServers": {
    "asc-mcp": {
      "command": "/Users/you/.mint/bin/asc-mcp"
    }
  }
}
```

MCP tools are available in Continue agent mode. See the [official Continue MCP documentation](https://docs.continue.dev/customize/deep-dives/mcp).

</details>

<details>
<summary><strong>Cursor</strong></summary>

Use `~/.cursor/mcp.json` for all projects or `.cursor/mcp.json` for one project:

```json
{
  "mcpServers": {
    "asc-mcp": {
      "command": "/Users/you/.mint/bin/asc-mcp"
    }
  }
}
```

Restart or refresh the MCP server from Cursor settings after editing the file. See the [official Cursor MCP documentation](https://cursor.com/docs/mcp).

</details>

<details>
<summary><strong>Devin Desktop (formerly Windsurf)</strong></summary>

Add the server to `~/.codeium/windsurf/mcp_config.json`. This example enables a 72-tool release subset, below Cascade's 100-tool limit:

```json
{
  "mcpServers": {
    "asc-mcp": {
      "command": "/Users/you/.mint/bin/asc-mcp",
      "args": [
        "--workers",
        "apps,builds,export_compliance,versions,reviews"
      ]
    }
  }
}
```

You can also disable individual tools in the client. Server-side worker filtering is recommended because it keeps the active catalog predictable. See the [official Devin Desktop MCP documentation](https://docs.devin.ai/desktop/cascade/mcp).

</details>

> [!IMPORTANT]
> `command` must point to the real executable. GUI clients often do not inherit shell aliases, PATH changes, or environment variables. Use an absolute path and prefer the default `companies.json` credential file.

## Worker Filtering

The server exposes **502 tools** across 33 App Store tool domains + 2 core domains. Some MCP clients impose a tool limit; Cascade in Devin Desktop currently allows 100 active tools. Use the 35 `--workers` filter keys to enable only the workers you need:

```bash
# Only load apps, builds, and version lifecycle tools
asc-mcp --workers apps,builds,versions

# App Store release preparation subset (99 tools, including always-on and build sub-workers)
asc-mcp --workers apps,accessibility,builds,export_compliance,versions,app_info,screenshots

# TestFlight review helpers can be loaded separately (49 tools)
asc-mcp --workers apps,builds,beta_app,pre_release

# Monetization focus
asc-mcp --workers apps,iap,subscriptions,pricing,promoted,review_submissions
```

`company` and `auth` workers are **always enabled** regardless of the filter (they provide core multi-account and authentication functionality).

When `builds` is enabled, it automatically includes `build_processing` and `build_beta` sub-workers.

## Read-Only Mode

Use `--read-only` when you want safe inspection without App Store Connect mutations:

```bash
asc-mcp --read-only
asc-mcp --read-only --workers apps,builds,reviews,analytics
```

In this mode, read tools such as `*_list`, `*_get`, `*_search`, `*_status`, `*_verify`, `*_parse`, `*_triage`, `auth_*`, analytics, and metrics remain available. Tools that can create, update, upload, submit, release, delete, revoke, clear, cancel, or otherwise mutate App Store Connect are blocked before their worker handler runs. `company_switch` remains available because it changes only the local active company context.

## OpenAPI Contract and Drift Tooling

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

The manifest is pinned to Apple API 4.4.1 by version, SHA-256, path count, and operation count. It currently maps 476 Apple operations, explicitly defers 424, and scopes out 363, covering all 1,263 operations without overlap. CI fails when the Apple document changes, a mapped operation moves or disappears, a public tool or worker drifts from the manifest, an input field loses its binding, response lineage becomes invalid, or a deferred decision expires. Unexposed optional Apple parameters are warnings so they remain visible in the generated backlog.

Manifest schema v2 also accounts for every optional Apple query and request-body input as publicly bound, internally controlled, intentionally omitted with a reviewed reason, or still unclassified. The checked-in `optionalInputCoveragePin` records the exact current totals and a SHA-256 digest of the sorted input identities and dispositions; `--strict` rejects a missing pin or any count- or identity-level drift. The pin makes phased remediation auditable and regression-safe, but it is not a claim that every optional Apple input is already public. The v4.1.3 pin is 2,905 total: 1,122 bound, 40 internally controlled, 1,743 intentionally omitted, and 0 unclassified. Its identity SHA-256 is `c975f4e4eebb62ec87864a73fbf72bb8841f644108e54e6ffb25168bcf2a2766`.

`--strict` is the merge- and tag-time release gate. Every declared `target` or `broken` tool remains an error in reports, and a regression test pins their exact state. The current baseline has no `target` or `broken` implementations and no implementation drift, so any implementation that leaves `asBuilt`, any structural contract error, or any optional-input coverage drift blocks both merges and releases. `--structural-strict` remains available only for local phased remediation work.

This gate proves operation identity, top-level MCP field ownership, required Apple inputs, typed internal values, and response source/pointer lineage. Full MCP type/enum/range parity and complete typed response schemas remain separate optimization phases; the current mapping status is 469 partial and 33 deprecated.

The older `openapi-coverage` command remains available for the high-level domain report in [`ASC-OPENAPI-COVERAGE-GENERATED.md`](ASC-OPENAPI-COVERAGE-GENERATED.md). The operation contract is the authoritative release gate.

**Available worker names:**

| Worker | Prefix | Tools | Description |
|--------|--------|-------|-------------|
| `company` | `company_` | 3 | Multi-account management |
| `auth` | `auth_` | 4 | JWT token tools |
| `apps` | `apps_` | 10 | App listing, metadata, localizations, search keyword IDs |
| `accessibility` | `accessibility_` | 6 | App Store accessibility declarations |
| `webhooks` | `webhooks_` | 11 | Webhook notifications, delivery diagnostics, and receiver helpers |
| `xcode_cloud` | `xcode_cloud_` | 42 | Xcode Cloud products, workflow management, build runs, artifacts, issues, test results, and SCM |
| `builds` | `builds_` | 4 | Build management |
| `build_uploads` | `build_uploads_` | 10 | Build upload parents, files, safe transfers, and recovery |
| `build_processing` | `builds_get_processing_*`, `builds_update_encryption`, `builds_check_readiness` | 4 | Build states, encryption |
| `export_compliance` | `export_compliance_` | 11 | Encryption declarations, document uploads, build linkage, readiness |
| `build_beta` | `builds_*_beta_*`, individual tester build tools | 11 | TestFlight localizations, notifications |
| `versions` | `app_versions_` | 17 | Version lifecycle, age ratings, submit, release |
| `reviews` | `reviews_` | 8 | Customer reviews and responses |
| `beta_groups` | `beta_groups_` | 15 | TestFlight groups and public-link recruitment criteria |
| `beta_feedback` | `beta_feedback_` | 8 | TestFlight feedback screenshots, crash submissions, crash logs |
| `beta_testers` | `beta_testers_` | 12 | Tester management |
| `iap` | `iap_` | 59 | In-app purchases, versioned metadata, pricing, availability, offer codes, review assets |
| `subscriptions` | `subscriptions_` | 99 | Subscription and group versions, pricing, plan availability, offers, assets |
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
| `screenshots` | `screenshots_` | 19 | Screenshots, previews, sets, and verified ordering |
| `custom_pages` | `custom_pages_` | 17 | Custom product pages, versions, localizations, and search keywords |
| `ppo` | `ppo_` | 15 | Product page optimization experiments, treatments, and localizations |
| `promoted` | `promoted_` | 10 | Promoted in-app purchases and verified ordering |
| `review_attachments` | `review_attachments_` | 4 | App Store review attachments |
| `review_submissions` | `review_submissions_` | 9 | Generic App Store review submissions and submission items |
| `metrics` | `metrics_` | 9 | Performance metrics, diagnostics, and TestFlight usage metrics |

### Tool Catalog Size

When an MCP client eagerly loads every tool definition, the approximate schema footprint is:

| Configuration | Tools | ~Tokens |
|---|---:|---:|
| All workers (default) | 502 | **~60,000** |
| Release workflow: `apps,builds,export_compliance,versions,reviews` | ~72 | ~8,900 |
| Monetization: `apps,iap,subscriptions,pricing` | 184 | ~21,100 |
| TestFlight: `apps,builds,beta_groups,beta_testers` | ~63 | ~7,100 |
| Marketing: `apps,screenshots,custom_pages,ppo,promoted` | ~78 | ~8,800 |
| `--workers apps` | 17 | ~2,100 |

**Heaviest workers:** Subscriptions (99 tools), InAppPurchases (59 tools), Xcode Cloud (42 tools), Screenshots (19 tools), Provisioning (17 tools).

Exact cost depends on the MCP host's serialization, tokenizer, and tool-discovery strategy. Modern clients may defer schemas until they are needed. Use `--workers` when the client enforces a tool limit or when you want a smaller, more focused catalog.

## Available Tools

**502 tools** organized across 33 App Store tool domains + 2 core domains (use the 35 `--workers` filter keys — see [Worker Filtering](#worker-filtering)):

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
<summary><strong>Apps Management</strong> — 10 tools</summary>

| Tool | Description |
|------|-------------|
| `apps_list` | List all applications with filtering |
| `apps_get_details` | Get detailed app information |
| `apps_search` | Search apps by name or Bundle ID |
| `apps_list_versions` | List all versions with states |
| `apps_get_metadata` | Get localized metadata for a version |
| `apps_list_search_keywords` | List canonical App Store search keyword IDs for custom-page targeting |
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
<summary><strong>Xcode Cloud</strong> — 42 tools</summary>

| Tool | Description |
|------|-------------|
| `xcode_cloud_products_list` | List Xcode Cloud products |
| `xcode_cloud_products_get` | Get an Xcode Cloud product |
| `xcode_cloud_products_delete` | Preview or permanently delete an Xcode Cloud product with confirmation safeguards |
| `xcode_cloud_app_product_get` | Get the Xcode Cloud product associated with an app |
| `xcode_cloud_product_app_get` | Get the app associated with an Xcode Cloud product |
| `xcode_cloud_product_primary_repositories_list` | List primary repositories attached to a product |
| `xcode_cloud_product_additional_repositories_list` | List additional repositories attached to a product |
| `xcode_cloud_product_workflows_list` | List workflows for a product |
| `xcode_cloud_product_build_runs_list` | List build runs for a product |
| `xcode_cloud_workflows_get` | Get a workflow |
| `xcode_cloud_workflows_create` | Create an Xcode Cloud workflow |
| `xcode_cloud_workflows_update` | Update an Xcode Cloud workflow |
| `xcode_cloud_workflows_delete` | Preview or permanently delete a workflow with confirmation safeguards |
| `xcode_cloud_workflow_repository_get` | Get the repository used by a workflow |
| `xcode_cloud_workflow_build_runs_list` | List build runs for a workflow |
| `xcode_cloud_build_runs_get` | Get a build run |
| `xcode_cloud_build_runs_start` | Start or rebuild an Xcode Cloud build |
| `xcode_cloud_build_run_actions_list` | List build actions for a run |
| `xcode_cloud_build_run_builds_list` | List App Store Connect builds created by a run |
| `xcode_cloud_actions_get` | Get a build action |
| `xcode_cloud_action_build_run_get` | Get the build run that owns a build action |
| `xcode_cloud_action_artifacts_list` | List artifacts for an action |
| `xcode_cloud_action_issues_list` | List issues for an action |
| `xcode_cloud_action_test_results_list` | List test results for an action |
| `xcode_cloud_artifacts_get` | Get an artifact |
| `xcode_cloud_issues_get` | Get an issue |
| `xcode_cloud_test_results_get` | Get a test result |
| `xcode_cloud_xcode_versions_list` | List available Xcode versions |
| `xcode_cloud_xcode_versions_get` | Get an Xcode version |
| `xcode_cloud_xcode_version_macos_versions_list` | List macOS versions compatible with an Xcode version |
| `xcode_cloud_macos_versions_list` | List available macOS versions |
| `xcode_cloud_macos_versions_get` | Get a macOS version |
| `xcode_cloud_macos_version_xcode_versions_list` | List Xcode versions compatible with a macOS version |
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
<summary><strong>Build Uploads</strong> — 10 tools</summary>

| Tool | Description |
|------|-------------|
| `build_uploads_list` | List an app's Build Upload parents with filters, sparse fields, includes, and strict pagination |
| `build_uploads_get` | Get one Build Upload with processing diagnostics and optional included resources |
| `build_uploads_create` | Create a Build Upload parent without replaying an ambiguous POST |
| `build_uploads_delete` | Delete a Build Upload parent after exact ID confirmation |
| `build_uploads_list_files` | List file reservations under one Build Upload with strict pagination |
| `build_uploads_get_file` | Get one Build Upload File and its delivery state |
| `build_uploads_reserve_file` | Reserve one exact file without replaying an ambiguous POST |
| `build_uploads_commit_file` | Commit checksum or uploaded-state changes with omission and null preserved separately |
| `build_uploads_upload_file` | Transfer a new or existing reservation from an immutable local snapshot |
| `build_uploads_upload` | Run parent creation, reservation, transfer, commit, and processing reconciliation |

Compound uploads retain the same lowercase MD5 fingerprint from reservation through recovery. Explicit resume and recovered-continuation instructions carry `expected_md5`; the next invocation verifies a fresh immutable snapshot against it before any Apple request or transfer. An existing reservation already marked `UPLOAD_COMPLETE` or `COMPLETE` is accepted only when Apple's `sourceFileChecksums.file` MD5 matches that snapshot; missing, unsupported, or mismatched evidence is retained for inspection without another transfer, commit, or delete. Presigned operations retry only when their method is `PUT`; redirects, `POST`, and unknown methods are not replayed. If an ambiguous create is uniquely recovered, the workflow stops and returns its resource ID for explicit continuation. Transfer credentials stay redacted unless `include_sensitive_details` is explicitly enabled on a direct read.

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
<summary><strong>TestFlight Beta Groups</strong> — 15 tools</summary>

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
| `beta_groups_get_recruitment_criteria` | Get the public-link recruitment criteria attached to a beta group |
| `beta_groups_create_recruitment_criteria` | Create device-family and OS-version recruitment criteria |
| `beta_groups_update_recruitment_criteria` | Replace or explicitly clear recruitment filters |
| `beta_groups_delete_recruitment_criteria` | Delete recruitment criteria after exact criterion-ID confirmation |
| `beta_groups_list_recruitment_options` | List device families and OS versions Apple currently permits |
| `beta_groups_check_recruitment_compatibility` | Check whether a group has a build compatible with its criteria |

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
<summary><strong>In-App Purchases</strong> — 59 tools</summary>

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
| `iap_create_version` | Create a reviewable IAP metadata version |
| `iap_get_version` | Get an IAP version and its review state |
| `iap_list_versions` | List reviewable versions for an IAP |
| `iap_list_version_localizations` | List localizations owned by an IAP version |
| `iap_create_version_localization` | Create a localization for an IAP version |
| `iap_get_version_localization` | Get an IAP version localization |
| `iap_update_version_localization` | Update nullable text on an IAP version localization |
| `iap_delete_version_localization` | Delete an IAP version localization |
| `iap_get_version_image` | Get the singular image related to an IAP version |
| `iap_list_version_images` | List every image resource owned by an IAP version with strict continuation support |
| `iap_upload_version_image` | Upload, commit, and reconcile an immutable IAP version image |
| `iap_get_version_image_resource` | Get a version-scoped IAP image resource |
| `iap_delete_version_image` | Delete a version-scoped IAP image |

The legacy product-scoped localization, submission, and image tools remain callable for compatibility. Apple 4.4.1 deprecates `iap_list_localizations`, `iap_create_localization`, `iap_update_localization`, `iap_delete_localization`, `iap_submit_for_review`, `iap_upload_image`, `iap_get_image`, `iap_delete_image`, and `iap_list_images`; successful responses identify the versioned replacement tools. For localization creation, promotional image upload, and review submission, first use `iap_list_versions`, call `iap_create_version` only when a new metadata version is needed, and pass that version ID to the downstream versioned tool. These compatibility calls never create or select a version automatically.

If Apple may have accepted a version or version-localization create but the response is lost or cannot be decoded, the tool returns `write_outcome: not_confirmed` and `retrySafe: false` with the requested identity plus list/get inspection steps. Inspect before retrying to avoid duplicate metadata resources.

</details>

<details>
<summary><strong>Subscriptions</strong> — 99 tools</summary>

Includes subscription and group metadata versions, version-owned localizations and images, plan-type-aware availability, territory-aware prices, price points and adjusted equalizations, promoted purchase reads, inventory/pricing helpers, intro offers, promotional offers, offer codes, one-time/custom codes, win-back offers, and review screenshots. All former public `offer_codes_*`, `intro_offers_*`, `promo_offers_*`, and `winback_*` functionality is exposed through `subscriptions_*`.

Apple 4.4.1 also deprecates the legacy product- or group-scoped localization, image, and submission tools. They remain callable for compatibility, return explicit replacement guidance on success, and never create or select a metadata version automatically. New integrations should use `subscriptions_create_version` or `subscriptions_create_group_version`, the corresponding version-localization/image tools, and the generic `review_submissions_*` workflow.

Subscription version, group-version, localization, and plan-availability creates use the same non-idempotent recovery contract: an ambiguous Apple write returns `write_outcome: not_confirmed`, `retrySafe: false`, the requested fingerprint, and deterministic collection/get inspection guidance.

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
<summary><strong>Screenshots & Previews</strong> — 19 tools</summary>

| Tool | Description |
|------|-------------|
| `screenshots_list_sets` | List screenshot sets |
| `screenshots_get_set` | Get a screenshot set by ID |
| `screenshots_create_set` | Create a screenshot set |
| `screenshots_delete_set` | Delete a screenshot set |
| `screenshots_list` | List screenshots in a set |
| `screenshots_upload` | Upload a screenshot |
| `screenshots_get` | Get screenshot details |
| `screenshots_delete` | Delete a screenshot |
| `screenshots_reorder` | Reorder screenshots in a set |
| `screenshots_list_preview_sets` | List app preview sets |
| `screenshots_get_preview_set` | Get an app preview set by ID |
| `screenshots_create_preview_set` | Create a preview set |
| `screenshots_delete_preview_set` | Delete a preview set |
| `screenshots_upload_preview` | Upload an app preview |
| `screenshots_get_preview` | Get preview details |
| `screenshots_list_previews` | List previews in a preview set |
| `screenshots_reorder_previews` | Reorder every preview in a set with membership and postflight verification |
| `screenshots_upload_batch` | Upload screenshots in a batch |
| `screenshots_delete_preview` | Delete a preview |

</details>

<details>
<summary><strong>Custom Product Pages</strong> — 17 tools</summary>

| Tool | Description |
|------|-------------|
| `custom_pages_list` | List custom product pages |
| `custom_pages_get` | Get page details |
| `custom_pages_create` | Create a custom page |
| `custom_pages_update` | Update a custom page |
| `custom_pages_delete` | Delete a custom page |
| `custom_pages_list_versions` | List page versions |
| `custom_pages_get_version` | Get a page version by ID |
| `custom_pages_create_version` | Create a page version |
| `custom_pages_update_version` | Update a page version |
| `custom_pages_list_localizations` | List version localizations |
| `custom_pages_get_localization` | Get a localization by ID |
| `custom_pages_create_localization` | Create a localization |
| `custom_pages_update_localization` | Update a localization |
| `custom_pages_delete_localization` | Delete a localization after exact confirmation |
| `custom_pages_list_search_keywords` | List search keyword IDs assigned to a localization |
| `custom_pages_add_search_keywords` | Add search keyword relationships |
| `custom_pages_remove_search_keywords` | Remove search keyword relationships after exact confirmation |

</details>

<details>
<summary><strong>Product Page Optimization (A/B Tests)</strong> — 15 tools</summary>

| Tool | Description |
|------|-------------|
| `ppo_list_experiments` | List A/B test experiments |
| `ppo_list_version_experiments` | List V2 experiments for an App Store version |
| `ppo_get_experiment` | Get experiment details |
| `ppo_create_experiment` | Create an experiment |
| `ppo_update_experiment` | Update/start/stop experiment |
| `ppo_delete_experiment` | Delete an experiment |
| `ppo_list_treatments` | List experiment treatments |
| `ppo_get_treatment` | Get a treatment by ID |
| `ppo_create_treatment` | Create a treatment variant |
| `ppo_update_treatment` | Update a treatment variant |
| `ppo_delete_treatment` | Delete a treatment after exact confirmation |
| `ppo_list_treatment_localizations` | List treatment localizations |
| `ppo_get_treatment_localization` | Get a treatment localization by ID |
| `ppo_create_treatment_localization` | Create treatment localization |
| `ppo_delete_treatment_localization` | Delete a treatment localization after exact confirmation |

</details>

<details>
<summary><strong>Promoted Purchases</strong> — 10 tools</summary>

| Tool | Description |
|------|-------------|
| `promoted_list` | List promoted purchases for an app |
| `promoted_get` | Get promotion details |
| `promoted_create` | Create a promotion |
| `promoted_update` | Update promotion visibility or enabled state |
| `promoted_delete` | Delete a promotion |
| `promoted_reorder` | Replace and verify the complete promoted-purchase order for an app |
| `promoted_upload_image` | Deprecated: returns migration guidance; the endpoint is absent from pinned Apple OpenAPI 4.4.1 |
| `promoted_get_image` | Deprecated: returns migration guidance; the endpoint is absent from pinned Apple OpenAPI 4.4.1 |
| `promoted_delete_image` | Deprecated: returns migration guidance; the endpoint is absent from pinned Apple OpenAPI 4.4.1 |
| `promoted_get_image_for_purchase` | Deprecated: returns migration guidance; the relationship is absent from pinned Apple OpenAPI 4.4.1 |

</details>

<details>
<summary><strong>Review Attachments</strong> — 4 tools</summary>

Includes App Store review attachment upload, get, delete, and list tools.

</details>

<details>
<summary><strong>Review Submissions</strong> — 9 tools</summary>

| Tool | Description |
|------|-------------|
| `review_submissions_list` | List generic review submissions for an app |
| `review_submissions_get` | Get one generic review submission |
| `review_submissions_create` | Create a generic review submission for an app and platform |
| `review_submissions_list_items` | List items attached to a review submission |
| `review_submissions_add_item` | Attach a reviewable resource version to a submission |
| `review_submissions_update_item` | Update nullable `resolved` or `removed` state on a submitted item |
| `review_submissions_remove_item` | Remove an item from a submission |
| `review_submissions_submit` | Submit all attached items for review |
| `review_submissions_cancel` | Cancel a submitted generic review submission |

`review_submissions_add_item` reports success only when Apple's response confirms a valid item ID and exactly the requested relationship name, JSON:API type, and resource ID. Any mismatch is returned as an unconfirmed write with submission and item-list recovery steps.

</details>

<details>
<summary><strong>Performance Metrics</strong> — 9 tools</summary>

| Tool | Description |
|------|-------------|
| `metrics_app_perf` | Get app performance/power metrics |
| `metrics_build_perf` | Get build performance metrics |
| `metrics_build_diagnostics` | List diagnostics for a build |
| `metrics_get_diagnostic_logs` | Get diagnostic logs |
| `metrics_app_beta_tester_usage` | Get app TestFlight crash, session, and feedback metrics by beta tester |
| `metrics_group_beta_tester_usage` | Get beta-group TestFlight crash, session, and feedback metrics by beta tester |
| `metrics_group_public_link_usage` | Get public-link views, acceptance outcomes, criteria failures, and survey ratios |
| `metrics_tester_usage` | Get one tester's TestFlight usage metrics within an app |
| `metrics_build_beta_usage` | Get build TestFlight crash, install, session, feedback, and invitation metrics |

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
└── Workers/                        # MCP tool implementations (39 Swift worker classes + MainWorker router)
    ├── MainWorker/WorkerManager    #   Central tool registry & routing
    ├── CompaniesWorker/            #   company_* tools
    ├── AuthWorker/                 #   auth_* tools
    ├── AppsWorker/                 #   apps_* tools
    ├── AccessibilityWorker/        #   accessibility_* tools
    ├── WebhooksWorker/             #   webhooks_* tools
    ├── XcodeCloudWorker/           #   xcode_cloud_* tools
    ├── BuildsWorker/               #   builds_* tools
    ├── BuildUploadsWorker/         #   build_uploads_* tools
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
    ├── ReviewSubmissionsWorker/    #   review_submissions_* tools
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

1. Run `~/.mint/bin/asc-mcp --version` to verify the installation independently of the MCP client.
2. Verify that the MCP client uses the absolute path to the installed executable.
3. For Codex, run `codex mcp list` and `codex mcp get asc-mcp --json`.
4. For Claude Code, run `claude mcp get asc-mcp` and `claude mcp list`.
5. Check either the configured `companies.json` file or the environment variables used by your chosen setup.
6. Ensure every `.p8` key path is absolute and the file exists.
7. Restart GUI clients after changing their MCP configuration, then inspect the client's MCP output log.

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

## Getting Help

Before opening a report, search the [existing issues](https://github.com/zelentsov-dev/asc-mcp/issues). If the problem is new, [open an issue](https://github.com/zelentsov-dev/asc-mcp/issues/new/choose) and include:

- macOS version and installation method;
- MCP client name and version;
- the selected `--workers` value, if any;
- the exact error message and the smallest reproducible request.

Remove Key IDs, Issuer IDs, private keys, signed URLs, tokens, and account data from logs before posting them. Report security vulnerabilities privately by following [SECURITY.md](SECURITY.md). For code contributions, see [CONTRIBUTING.md](CONTRIBUTING.md).

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
