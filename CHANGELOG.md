# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2025-02-18

### Changed

- **Public release preparation** — repository is now ready for open-source publication
- Updated all documentation version references to 1.4.0
- Fixed tool counts across README, CLAUDE.md, and tests to match actual implementations
- Documented `vendor_number` configuration for analytics tools
- Added `vendor_number` field to `companies.example.json`
- Updated contact email in CODE_OF_CONDUCT.md and SECURITY.md

### Added

- `CONTRIBUTING.md` — contribution guide with code conventions, worker structure, and PR checklist
- GitHub issue templates (bug report, feature request)
- GitHub pull request template
- CI badge in README

### Removed

- `ROADMAP.md`, `AUDIT_REPORT.md`, `AUDIT_PLAN.md`, `REF_PLAN.md`, `WORKERS_API_MAPPING.md` — internal working documents

## [1.3.0] - 2025-02-18

### Added

- `app_versions_get_phased_release` tool — get phased release info and ID
- Territory schedules in `app_versions_update` — set territory-specific release dates
- Unified locale/territory descriptions across all workers
- **208 tools** total (up from 207)

### Fixed

- Tool count documentation corrected to actual 207 (then 208 with new tool)

## [1.2.0] - 2025-02-18

### Added

- Linked product info in `promoted_get` response
- Actual price data in `subscriptions_list_prices` response

### Fixed

- Version state filter and iOS platform preference for metadata auto-select
- Removed duplicate `metrics_list_diagnostics` tool
- Marked `name` as required in `app_info_create_localization`

### Changed

- Improved tool descriptions for accuracy and clarity
- Translated all project documentation to English

## [1.1.1] - 2025-02-17

### Fixed

- Removed relative `companies.json` from default config paths (security improvement)

## [1.1.0] - 2025-02-17

### Added

- **8 new workers** + extended 3 existing workers (+77 tools):
  - SubscriptionsWorker (15 tools) — subscription CRUD, groups, localizations, prices
  - OfferCodesWorker (7 tools) — subscription offer codes, one-time codes
  - WinBackOffersWorker (5 tools) — win-back offers for subscriptions
  - ScreenshotsWorker (12 tools) — screenshots, previews, sets, reorder
  - CustomProductPagesWorker (10 tools) — custom product pages, versions, localizations
  - ProductPageOptimizationWorker (9 tools) — A/B test experiments, treatments
  - PromotedPurchasesWorker (5 tools) — promoted in-app purchases, images
  - MetricsWorker (4 tools) — performance/power metrics, diagnostics
- `analytics_app_summary` tool — combined app analytics in a single call
- `app_id` filter for sales reports (per-app summaries)
- Sales reports `version` parameter, `summary_only` mode, subscription summaries
- Gzip TSV report decoding into structured JSON with summaries
- `vendorNumber` in company config + `analytics_check_snapshot_status` tool
- `app_info_delete_localization` tool

### Fixed

- 11 API bugs across 6 workers (metrics, PPO, offer codes, win-back, custom pages, promoted)
- 5 API bugs round 2 (territory, linkage, diagnostics, promoted cleanup)
- 3 API bugs round 3 (offer codes FREE_TRIAL, custom pages inline, diagnostics raw fallback)
- Metrics BATTERY/TERMINATION/ANIMATION raw JSON fallback
- Custom pages `${local-id}` format for inline includes

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
