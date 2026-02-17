# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-02-17

### Added

- **17 workers** with ~109 tools covering the full App Store Connect API
- **Multi-account support** via `companies.json` configuration
- **Worker filtering** with `--workers` flag for tool-limited MCP clients
- **JWT authentication** with ES256 signing and automatic 20-minute refresh
- **HTTP client** as actor with retry logic, 429 rate-limit handling, and idempotent request support
- **Pagination** helper for traversing large API result sets

#### Workers

- **CompaniesWorker** (3 tools) — multi-account management, switching, listing
- **AuthWorker** (4 tools) — JWT token generation, validation, refresh
- **AppsWorker** (9 tools) — app listing, metadata, localized descriptions, keywords
- **BuildsWorker** (4 tools) — build listing, details, individual build info
- **BuildBetaDetailsWorker** (9 tools) — TestFlight localizations, beta groups, notifications
- **BuildProcessingWorker** (5 tools) — build states, encryption declarations
- **AppLifecycleWorker** (12 tools) — version create/submit/release, phased rollout
- **ReviewsWorker** (8 tools) — customer reviews, responses, statistics
- **BetaGroupsWorker** (9 tools) — TestFlight groups CRUD, testers, builds
- **BetaTestersWorker** (6 tools) — tester management, search, invite
- **InAppPurchasesWorker** (12 tools) — IAP and subscriptions CRUD, localizations, submit
- **ProvisioningWorker** (17 tools) — bundle IDs, devices, certificates, profiles, capabilities
- **AppInfoWorker** (6 tools) — app info, categories, age rating, localizations
- **PricingWorker** (6 tools) — territories, availability, price points and schedules
- **UsersWorker** (6 tools) — team members, roles, invitations
- **AppEventsWorker** (6 tools) — in-app events CRUD, localizations
- **AnalyticsWorker** (4 tools) — sales reports, financial reports, analytics

### Security

- SSRF protection for pagination URL validation
- Sensitive credential masking in MCP responses
- HTTPS-only communication with App Store Connect API
- JWT tokens held in memory only, never persisted

### Testing

- 295+ unit tests using Swift Testing framework
- Test fixtures with placeholder credentials (no real keys)
