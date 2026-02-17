# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language
Response language: Russian
Comment language: English    

## Project Overview

MCP (Model Context Protocol) server for App Store Connect API integration, designed for Claude Code CLI. This server provides tools to manage iOS/macOS apps through App Store Connect.

## Build and Run Commands

```bash
# Build the project
swift build

# Run the MCP server (requires environment variables)
./.build/debug/asc-mcp

# Run tests/debug mode
./.build/debug/asc-mcp --test

# Clean build
swift package clean
```

## Environment Configuration

Uses `companies.json` for multi-account configuration. Each company entry contains `keyID`, `issuerID`, and `privateKeyPath`.

## Architecture

### Core Components

**WorkerManager** (`Workers/MainWorker/WorkerManager.swift`) — central registry, routes tool calls by prefix.

**Workers** (17 workers, ~109 tools):

| Worker | Prefix | Tools | Domain |
|--------|--------|-------|--------|
| CompaniesWorker | `company_` | 3 | Multi-account management |
| AuthWorker | `auth_` | 4 | JWT tokens |
| AppsWorker | `apps_` | 9 | App listing, metadata, localizations, create/delete localization |
| BuildsWorker | `builds_` | 4 | Build management |
| BuildBetaDetailsWorker | `builds_*_beta_` | 9 | TestFlight localizations, notifications, beta groups |
| BuildProcessingWorker | `builds_*_processing_` | 5 | Build states, encryption |
| AppLifecycleWorker | `app_versions_` | 12 | Versions, submit, release, phased rollout |
| ReviewsWorker | `reviews_` | 8 | Customer reviews and responses |
| BetaGroupsWorker | `beta_groups_` | 9 | TestFlight groups CRUD, testers, builds |
| InAppPurchasesWorker | `iap_` | 12 | IAP, subscriptions, localizations CRUD, submit |
| ProvisioningWorker | `provisioning_` | 17 | Bundle IDs, devices, certificates, profiles, capabilities |
| BetaTestersWorker | `beta_testers_` | 6 | Tester management, search, invite |
| AppInfoWorker | `app_info_` | 6 | App info, categories, localizations |
| PricingWorker | `pricing_` | 6 | Territories, availability, price points/schedule |
| UsersWorker | `users_` | 6 | Team members, roles, invitations |
| AppEventsWorker | `app_events_` | 6 | In-app events CRUD, localizations |
| AnalyticsWorker | `analytics_` | 4 | Sales/financial reports, analytics requests |

**Services**: HTTPClient (actor, GET/POST/PATCH/PUT/DELETE + retry with 429), JWTService (ES256)

### Key Implementation Details

1. **Swift 6 Compliance**: All types `Sendable`, proper actor isolation
2. **JWT Auth**: CryptoKit ES256, tokens expire after 20 min
3. **Worker Pattern**: 3 files per worker (Main + ToolDefinitions + Handlers)
4. **Routing**: WorkerManager routes by tool name prefix
5. **Error Handling**: Custom `ASCError` type

## API Constraints

- **No emojis** in metadata fields (What's New, Description, etc.)
- **Version states**: 
  - `READY_FOR_SALE`: Published, read-only
  - `PREPARE_FOR_SUBMISSION`: Editable
  - `WAITING_FOR_REVIEW`, `IN_REVIEW`: Read-only
- **Locale codes**: Use standard format (en-US, ru-RU, de-DE, etc.)

## Testing

Test mode (`--test` flag) performs:
1. Lists app versions to find editable one
2. If found, updates What's New field
3. Verifies the update succeeded

## Common Tasks

### Adding New Tool

1. Implement method in appropriate Worker (e.g., `AppsWorker+Handlers.swift`)
2. Add tool definition method in Worker's tool definitions file (e.g., `AppsWorker+ToolDefinitions.swift`)
3. Register the tool in Worker's `getTools()` method
4. Add case to Worker's `handleTool()` switch
5. No changes needed in WorkerManager - it automatically routes by prefix

### Debugging API Issues

- Check version state (must be PREPARE_FOR_SUBMISSION for edits)
- Verify locale exists for the version
- Remove any emojis from text fields
- Check JWT token expiration (20 minutes)

## Important Files

- `main.swift`: Entry point with test mode
- `Workers/MainWorker/WorkerManager.swift`: Tool registry and routing
- `Models/`: API response/request models (AppStoreConnect, Builds, InAppPurchases, Provisioning)
- `Services/HTTPClient.swift`: HTTP actor with JWT auth and retry logic

## Development Workflow Rules

### Testing Approach
- **ALWAYS test as real MCP**: When testing functionality, use actual MCP commands as if you're a real user working with the server
- Test edge cases and error scenarios
- Verify responses contain all necessary data for practical use

### Development Process
1. **After making changes and building the project:**
   - Always respond: "✅ Готово к перезагрузке MCP"
   - Wait for user confirmation: "я перезагрузил" or similar
   - Then proceed with testing via MCP commands
   - Fix any issues found during testing

2. **After implementing features:**
   - Explain what each method returns
   - Describe practical use cases for the returned data
   - Example: "Метод `builds_list` возвращает список билдов с их статусами и датами. Это нужно для выбора билда для TestFlight или отправки в App Store"

### Code Documentation Requirements
- **MANDATORY**: Comment all public methods with:
  ```swift
  /// Brief description of what the method does
  /// - Returns: Description of return value and its structure
  /// - Throws: What errors can be thrown
  ```
- Document complex logic inline
- Add usage examples for non-obvious methods
