# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-03-24

### Breaking Changes

- **Renamed upload tools** — reserve-only tools replaced with full-cycle uploads:
  - `screenshots_create` → `screenshots_upload` (now accepts `file_path` instead of `file_name`/`file_size`)
  - `screenshots_create_preview` → `screenshots_upload_preview` (same)
  - `iap_create_review_screenshot` → `iap_upload_review_screenshot` (same)
- All upload tools now perform the complete 3-step cycle (reserve → upload chunks → commit) instead of returning raw `uploadOperations`

### Added

#### New Infrastructure

- **UploadService** — universal file upload engine for App Store Connect assets
  - Reads files from disk, computes MD5 checksums
  - Uploads chunks in parallel via `TaskGroup` to presigned URLs (no JWT required)
  - Handles the full reserve → upload → commit lifecycle

#### New Workers (8)

- **IntroductoryOffersWorker** (`intro_offers_*`, 4 tools) — subscription introductory offers (free trial, pay-as-you-go, pay-up-front) CRUD
- **PromotionalOffersWorker** (`promo_offers_*`, 6 tools) — subscription promotional offers with inline price creation
- **SandboxTestersWorker** (`sandbox_*`, 3 tools) — sandbox tester management (list, update renewal rate, clear purchase history)
- **BetaAppWorker** (`beta_app_*`, 10 tools) — beta app localizations (5), beta review submissions (3), beta review details (2)
- **PreReleaseVersionsWorker** (`pre_release_*`, 3 tools) — pre-release version listing, details, associated builds
- **BetaLicenseAgreementsWorker** (`beta_license_*`, 3 tools) — TestFlight license agreement text management
- **ReviewAttachmentsWorker** (`review_attachments_*`, 4 tools) — App Store review attachments with full upload support

#### Extended Workers (12)

- **SubscriptionsWorker** (15 → 29 tools):
  - +5 subscription group localizations (CRUD)
  - +1 subscription price deletion
  - +3 subscription image upload/get/delete (full cycle)
  - +3 subscription review screenshot upload/get/delete (full cycle)
  - +2 list images, get review screenshot by subscription
- **InAppPurchasesWorker** (17 → 24 tools):
  - +2 IAP availability (set/get)
  - +3 IAP image upload/get/delete (full cycle)
  - +1 IAP review screenshot upload (full cycle, renamed)
  - +1 IAP review screenshot delete
  - +1 IAP list images
- **BetaTestersWorker** (6 → 12 tools):
  - +1 send/resend TestFlight invitation
  - +2 add/remove tester from beta groups
  - +2 add/remove tester from builds
  - +1 remove tester from app
- **BuildBetaDetailsWorker** (8 → 11 tools):
  - +3 individual testers (add/remove/list per build)
- **ScreenshotsWorker** (12 → 16 tools):
  - Replaced reserve-only uploads with full-cycle uploads
  - +1 get screenshot details
  - +1 get preview details
  - +1 list previews in a set
  - +1 batch upload (multiple screenshots in one call)
- **PromotedPurchasesWorker** (5 → 9 tools):
  - +3 promoted purchase image upload/get/delete (full cycle)
  - +1 get image by promoted purchase ID
- **AppLifecycleWorker** (13 → 14 tools):
  - +1 version deletion (PREPARE_FOR_SUBMISSION state only)
- **ReviewsWorker** (7 → 8 tools):
  - +1 AI-generated customer review summarizations
- **UsersWorker** (7 → 10 tools):
  - +3 visible apps (list/add/remove per user)
- **AppInfoWorker** (7 → 10 tools):
  - +3 EULA management (get/create/update)
- **OfferCodesWorker** (7 → 10 tools):
  - +3 custom codes (create/get/deactivate)
- **PricingWorker** (6 → 9 tools):
  - +3 App Availabilities v2 (create, get, list territory availabilities)

#### Upload Support (8 asset types, all full-cycle)

| Asset Type | Upload | Get | Delete | List |
|------------|--------|-----|--------|------|
| App Screenshots | `screenshots_upload` | `screenshots_get` | `screenshots_delete` | `screenshots_list` |
| App Previews | `screenshots_upload_preview` | `screenshots_get_preview` | `screenshots_delete_preview` | `screenshots_list_previews` |
| IAP Images | `iap_upload_image` | `iap_get_image` | `iap_delete_image` | `iap_list_images` |
| IAP Review Screenshots | `iap_upload_review_screenshot` | `iap_get_review_screenshot` | `iap_delete_review_screenshot` | — |
| Subscription Images | `subscriptions_upload_image` | `subscriptions_get_image` | `subscriptions_delete_image` | `subscriptions_list_images` |
| Sub Review Screenshots | `subscriptions_upload_review_screenshot` | `subscriptions_get_review_screenshot` | `subscriptions_delete_review_screenshot` | — |
| Promoted Purchase Images | `promoted_upload_image` | `promoted_get_image` | `promoted_delete_image` | — |
| Review Attachments | `review_attachments_upload` | `review_attachments_get` | `review_attachments_delete` | `review_attachments_list` |

### Fixed

- `beta_app_list_submissions` now requires `build_id` (Apple API requires `filter[build]`)
- `reviews_summarizations` now sends required `filter[platform]` parameter
- `builds_list_individual_testers` routing in WorkerManager (was falling through to BuildsWorker)
- `intro_offers_create` description now warns about MISSING_METADATA state requirement
- `app_info_get_eula` returns clear error message when no EULA is configured

### Testing

- **436 tests** across 31 suites (up from 393)
- Added tool definition, routing, and parameter validation tests for all new workers
- Updated aggregate uniqueness and description tests

### Summary

| Metric | v1.4.0 | v2.0.0 | Change |
|--------|--------|--------|--------|
| Workers | 25 | 33 | +8 |
| Tools | 208 | 293 | +85 (+41%) |
| Tests | 393 | 436 | +43 |

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
