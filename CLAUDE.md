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

# Run all unit tests (435 tests)
swift test

# Run the MCP server (requires environment variables or companies.json)
./.build/debug/asc-mcp

# Run with worker filtering (for clients with tool limits)
./.build/debug/asc-mcp --workers apps,builds,versions,reviews

# Run integration tests
./.build/debug/asc-mcp --test

# Clean build
swift package clean
```

## Environment Configuration

Three config methods (checked in priority order):
1. `--companies /path/to/companies.json` (CLI argument)
2. `ASC_MCP_COMPANIES` env var → path to JSON file
3. Default JSON: `~/.config/asc-mcp/companies.json`
4. `ASC_COMPANY_1_KEY_ID`, `ASC_COMPANY_2_KEY_ID`... (multi-company env vars)
5. `ASC_KEY_ID` + `ASC_ISSUER_ID` + `ASC_PRIVATE_KEY_PATH` (single company env vars)

Each company needs: `keyID`, `issuerID`, `privateKeyPath` (path to `.p8` file).

## Architecture

### Core Components

**WorkerManager** (`Workers/MainWorker/WorkerManager.swift`) — central registry, routes tool calls by prefix.

**Workers** (33 workers, 284 tools):

| Worker | Prefix | Tools | Domain |
|--------|--------|-------|--------|
| CompaniesWorker | `company_` | 3 | Multi-account management |
| AuthWorker | `auth_` | 4 | JWT tokens |
| AppsWorker | `apps_` | 9 | App listing, metadata, localizations |
| BuildsWorker | `builds_` | 4 | Build management |
| BuildBetaDetailsWorker | `builds_*_beta_` | 11 | TestFlight localizations, notifications, beta groups, individual testers |
| BuildProcessingWorker | `builds_*_processing_` | 4 | Build states, encryption |
| AppLifecycleWorker | `app_versions_` | 14 | Versions, submit, release, phased rollout, delete |
| ReviewsWorker | `reviews_` | 8 | Customer reviews, responses, AI summarizations |
| BetaGroupsWorker | `beta_groups_` | 9 | TestFlight groups CRUD, testers, builds |
| InAppPurchasesWorker | `iap_` | 22 | IAP, subscriptions, localizations, prices, screenshots, availability, images |
| ProvisioningWorker | `provisioning_` | 17 | Bundle IDs, devices, certificates, profiles, capabilities |
| BetaTestersWorker | `beta_testers_` | 12 | Tester management, search, invite, relationships, invitations |
| AppInfoWorker | `app_info_` | 10 | App info, categories, localizations, EULA |
| PricingWorker | `pricing_` | 9 | Territories, availability, price points/schedule, app availabilities v2 |
| UsersWorker | `users_` | 10 | Team members, roles, invitations, visible apps |
| AppEventsWorker | `app_events_` | 9 | In-app events CRUD, localizations |
| AnalyticsWorker | `analytics_` | 11 | Sales/financial reports, app summary, analytics reports/instances/segments, snapshot status |
| SubscriptionsWorker | `subscriptions_` | 27 | Subscription CRUD, groups, localizations, prices, submit, group localizations, images, review screenshots |
| OfferCodesWorker | `offer_codes_` | 10 | Subscription offer codes, one-time codes, custom codes |
| WinBackOffersWorker | `winback_` | 5 | Win-back offers for subscriptions |
| IntroductoryOffersWorker | `intro_offers_` | 4 | Introductory offers (free trial, pay-as-you-go, pay-up-front) |
| PromotionalOffersWorker | `promo_offers_` | 6 | Promotional offers for subscriptions |
| SandboxTestersWorker | `sandbox_` | 3 | Sandbox testers (list, update, clear purchase history) |
| BetaAppWorker | `beta_app_` | 10 | Beta app localizations, review submissions, review details |
| PreReleaseVersionsWorker | `pre_release_` | 3 | Pre-release versions (list, get, builds) |
| BetaLicenseAgreementsWorker | `beta_license_` | 3 | Beta license agreements (list, get, update) |
| ScreenshotsWorker | `screenshots_` | 12 | Screenshots, previews, sets, reorder |
| CustomProductPagesWorker | `custom_pages_` | 10 | Custom product pages, versions, localizations |
| ProductPageOptimizationWorker | `ppo_` | 9 | A/B test experiments, treatments |
| PromotedPurchasesWorker | `promoted_` | 8 | Promoted in-app purchases, images upload |
| ReviewAttachmentsWorker | `review_attachments_` | 4 | App Store review attachments (upload, get, delete, list) |
| MetricsWorker | `metrics_` | 4 | Performance/power metrics, diagnostics |

**Services**: HTTPClient (actor, GET/POST/PATCH/PUT/DELETE + retry with 429), JWTService (ES256), CompaniesManager

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

### Unit Tests (Swift Testing)

```bash
swift test    # Run all 435 tests across 31 suites
```

Test categories:
- **Worker tests** (`Tests/ASCMCPTests/Workers/`):
  - `WorkerToolDefinitionsTests` — tool count and name correctness per worker
  - `WorkerRoutingTests` — unknown tool throws `MCPError.methodNotFound`
  - `ParameterValidationTests` — missing required params returns `isError`
- **Model tests** (`Tests/ASCMCPTests/Models/`) — decode, roundtrip, edge cases
- **Service tests** (`Tests/ASCMCPTests/Services/`) — JWT generation
- **Helper tests** (`Tests/ASCMCPTests/HelperTests/`) — JSON formatting, pagination
- **Core tests** (`Tests/ASCMCPTests/Core/`) — ASCError, config models

Test infrastructure: `TestFactory` (`Tests/ASCMCPTests/Helpers/TestHelpers.swift`) — creates mock HTTPClient, JWTService, loads fixtures.

### Integration Test Mode

```bash
./.build/debug/asc-mcp --test              # Test company switching
./.build/debug/asc-mcp --test-metadata      # Test metadata update
```

## Common Tasks

### Adding New Tool to Existing Worker

1. Implement handler in `Worker+Handlers.swift`
2. Add tool definition in `Worker+ToolDefinitions.swift`
3. Register in worker's `getTools()` array
4. Add case to worker's `handleTool()` switch
5. No changes needed in WorkerManager — it automatically routes by prefix

### Adding New Worker

1. Create directory `Workers/MyWorker/` with 3 files:
   - `MyWorker.swift` — class, `getTools()`, `handleTool()` switch
   - `MyWorker+ToolDefinitions.swift` — tool schemas
   - `MyWorker+Handlers.swift` — handler implementations
2. Create models in `Models/MyDomain/MyModels.swift`
3. Register in `WorkerManager.swift`: property, init, `registerWorkers()` (ListTools + CallTool), `reinitializeWorkers()`, getter method
4. Add worker name to `EntryPoint.swift` → `validWorkers` set
5. Add prefix description to `Application.swift` → server instructions
6. Update tests: `WorkerToolDefinitionsTests`, `WorkerRoutingTests`, `ParameterValidationTests`

### Debugging API Issues

- Check version state (must be PREPARE_FOR_SUBMISSION for edits)
- Verify locale exists for the version
- Remove any emojis from text fields
- Check JWT token expiration (20 minutes)

## Important Files

- `EntryPoint.swift`: Entry point with `--workers` filtering and test modes
- `Core/Application.swift`: MCP server setup and initialization
- `Workers/MainWorker/WorkerManager.swift`: Tool registry and routing
- `Models/`: API response/request models organized by domain:
  - `AppStoreConnect/`, `Builds/`, `AppLifecycle/` — apps, versions, builds
  - `InAppPurchases/`, `Subscriptions/` — IAP, subscriptions, offer codes, win-back
  - `Marketing/` — screenshots, custom pages, PPO experiments, promoted purchases
  - `Metrics/`, `Analytics/`, `AppEvents/` — performance, reports, events
  - `Provisioning/`, `Pricing/`, `Users/`, `AppInfo/` — provisioning, pricing, users
  - `Shared/` — shared types (upload operations, image assets)
- `Services/HTTPClient.swift`: HTTP actor with JWT auth and retry logic
- `Services/CompaniesManager.swift`: Multi-account management
- `Services/JWTService.swift`: ES256 JWT token generation
- `Helpers/`: JSONFormatter, SafeJSONHelpers, PaginationHelper, StderrWriter

## Development Workflow Rules

### Testing Approach
- **ALWAYS test as real MCP**: When testing functionality, use actual MCP commands as if you're a real user working with the server
- Test edge cases and error scenarios
- Verify responses contain all necessary data for practical use

### Development Process
1. **After making changes and building the project:**
   - Always respond: "Ready to reload MCP"
   - Wait for user confirmation: "reloaded" or similar
   - Then proceed with testing via MCP commands
   - Fix any issues found during testing

2. **After implementing features:**
   - Explain what each method returns
   - Describe practical use cases for the returned data
   - Example: "The `builds_list` method returns a list of builds with their statuses and dates. This is useful for selecting a build for TestFlight or submitting to the App Store"

### Code Documentation Requirements
- **MANDATORY**: Comment all public methods with:
  ```swift
  /// Brief description of what the method does
  /// - Returns: Description of return value and its structure
  /// - Throws: What errors can be thrown
  ```
- Document complex logic inline
- Add usage examples for non-obvious methods
