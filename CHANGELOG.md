# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.12.0] - 2026-07-20

### Changed

- Beta App localization creates and updates preserve the same three states for all five nullable Apple feedback, marketing, privacy, tvOS privacy, and description attributes.
- Beta submission inspection uses Apple's build relationship endpoint as a bounded fallback when neither primary linkage nor an included Build resource is available.

### Fixed

- Reject blank or whitespace-padded required identifiers and inconsistent primary, included, or fallback Build linkage before returning a misleading success.
- Mark post-create lineage validation failures as committed and unsafe to retry, with an explicit submission-inspection path.
- Validate Beta App localization and review-submission continuation URLs against the concrete collection path, complete originating query, effective page size, exact query-name allowlist, and Apple's non-empty cursor.
- Emit fallback-specific output only when the relationship endpoint was actually required, keeping the public response lineage consistent with the operation manifest.

### Compatibility

- No public MCP tool or required input was added, removed, or renamed; existing concrete update values and scalar filters remain valid.
- Passing null to a nullable Beta App localization attribute now forwards an explicit JSON null to Apple; omitting the input continues to leave that attribute absent from the request.
- Required identifiers with empty values or surrounding whitespace now fail locally before network access.
- The operation manifest now maps 366 Apple operations, explicitly defers 534, and scopes out 363; the optional-input pin remains fully classified at 2,154 total with 0 unclassified.

## [3.11.0] - 2026-07-20

### Changed

- Custom Product Pages now expose visibility, version-state, and locale filters, the custom-page template relationship, and nullable version deep links.
- Product Page Optimization exposes experiment-state and treatment-locale filters; screenshot and preview collections expose Apple's display-type and owning-localization filters.
- App preview uploads preserve Apple's nullable poster-frame and MIME attributes, including explicit nulls, while retaining the existing `video/mp4` default when `mime_type` is omitted.
- Subscription writes preserve nullable introductory-offer dates and target plan type, price plan type and preservation state, and subscription period; introductory-offer listings also return the target plan type.
- Bound or explicitly classified all 63 remaining optional Apple 4.4.1 query and request-body inputs: 21 bound, 2 internally controlled, and 40 intentionally omitted with reviewed reasons.

### Fixed

- Validate every `next_url` across the 11 affected Custom Product Page, Product Page Optimization, promoted-purchase, screenshot, and preview collections against its concrete parent, non-empty cursor, and complete originating query.
- Reject missing or changed continuation controls, unexpected or duplicate query names, comma-injected relationship IDs, unsupported Apple media types, malformed dates, invalid plan or period values, and whitespace-normalized filters before network access.
- Preserve value, explicit null, and omission as distinct states for nullable preview and subscription inputs, and retain `deepLink`, linked-product, and target-plan response data in public results.

### Compatibility

- No public MCP tool or required input was added, removed, or renamed; this release adds optional inputs and widens existing nullable inputs without invalidating existing first-page calls.
- Existing app preview uploads that omit `mime_type` continue to send `video/mp4`; callers may now pass null to let Apple infer the value.
- Continuation calls for the affected collections must preserve the complete originating query and Apple's non-empty cursor in `next_url`.
- The strict contract pin records all 2,154 optional Apple inputs: 809 bound, 40 internally controlled, 1,305 intentionally omitted, and 0 unclassified.

## [3.10.0] - 2026-07-20

### Changed

- Xcode Cloud build-run build listings now expose Apple's build-number, expiration, processing-state, beta-review-state, encryption, pre-release version and platform, audience, app, beta-group, App Store version, build-ID, and multi-field sort controls; scalar and array inputs use Apple's comma-separated query encoding.
- Product build-run listings now expose Apple's related-build filter, and both product and workflow build-run listings accept one or multiple build IDs.
- Xcode Cloud build-run build listings now return Apple's `/meta/paging/total` value.
- Bound or explicitly classified all 31 previously unclassified optional Apple inputs associated with the audited Xcode Cloud workflows: 16 bound and 15 intentionally omitted with reviewed reasons.

### Fixed

- Validate every `next_url` across all 16 Xcode Cloud list tools against its concrete parent path, a non-empty cursor, and the complete originating query, including filters, includes, sort order, and effective page size.
- Reject missing or changed continuation controls, wrong parent paths, unexpected or duplicate query names, empty cursors, and duplicate boolean filter values before network access.

### Compatibility

- No public MCP tool or required input was added, removed, or renamed; this release adds 16 optional inputs across two existing tools and widens the existing workflow build filter from a scalar to scalar-or-array input.
- Existing first-page calls remain valid. Continuation calls must preserve the complete originating query and Apple's non-empty cursor in `next_url`.
- The strict contract pin records 2,154 optional Apple inputs: 788 bound, 38 internally controlled, 1,265 intentionally omitted, and 63 still queued for domain review.

## [3.9.0] - 2026-07-20

### Changed

- IAP and subscription catalog listings now expose Apple's remaining name, product-ID, state, type, related-subscription-state, and sort controls; scalar and array inputs use Apple's comma-separated query encoding.
- IAP and subscription localization listings now expose a bounded 1...200 page size.
- Bound or explicitly classified all 169 previously unclassified optional Apple inputs associated with the IAP and subscription commerce workflows: 22 bound, 31 internally controlled, and 116 intentionally omitted with reviewed reasons.

### Fixed

- Validate every `next_url` across the audited IAP and subscription catalog, localization, price, offer, code, image, territory, and pricing-summary collections against its concrete parent path, a non-empty cursor, and the complete originating query, including fixed includes, sparse fieldsets, relationship limits, filters, sort order, and effective page size.
- Reject missing or empty cursors, missing or changed continuation controls, duplicate query names, unexpected filters, comma-containing free-text filter values, invalid enum values, empty arrays, and duplicate array values before network access.

### Compatibility

- No public MCP tool or required input was added, removed, or renamed; this release adds 20 optional inputs across seven existing tools, and existing scalar state and type filters remain valid.
- Free-text filter values containing commas are rejected because Apple's `explode=false` array serialization reserves commas as item delimiters.
- Existing calls remain valid. Continuation calls must preserve the originating filters, sort order, effective page size, all fixed projection controls, and Apple's non-empty cursor in `next_url`.
- The strict contract pin records 2,154 optional Apple inputs: 772 bound, 38 internally controlled, 1,250 intentionally omitted, and 94 still queued for domain review.

## [3.8.0] - 2026-07-20

### Changed

- `apps_list` now exposes App ID, SKU, related App Store version, version-state, review-submission, platform, and Game Center existence filters from Apple API 4.4.1.
- `apps_list_versions`, `apps_list_localizations`, and `app_versions_list` now expose their remaining collection ID, version-string, state, platform, locale, and page-size controls while preserving them across `next_url` requests.
- `app_versions_create` and `app_versions_update` now preserve omission, explicit null, and Boolean values for Apple's deprecated `usesIdfa` attribute; deprecated Apple inputs are marked in the MCP schemas.

### Fixed

- Reject empty or malformed collection-filter arrays before network access instead of silently dropping invalid values.
- Bound or explicitly classified all 145 previously unclassified optional Apple inputs associated with Apps and App Lifecycle workflows, including related-resource limits, expansion controls, review-item relationships, and legacy age-rating fields.
- Limit exact-locale metadata update lookups to one matching localization while retaining the fixed ownership projection.

### Compatibility

- No public MCP tool or required input was added, removed, or renamed; this release adds 20 optional inputs across six existing tools.
- Existing calls remain valid. Continuation calls that use the new collection filters must repeat the same filter values and effective page size with Apple's returned `next_url`.
- The strict contract pin records 2,154 optional Apple inputs: 750 bound, 7 internally controlled, 1,134 intentionally omitted, and 263 still queued for domain review.

## [3.7.0] - 2026-07-20

### Changed

- Failed MCP tool calls now expose a canonical structured result with `success: false`, a stable `error` message, and `details`, while retaining the first human-readable text block.
- Error results preserve content annotations, non-text content, and MCP `_meta`, and append exactly one compact JSON text mirror for clients that do not consume `structuredContent`.
- Typed output schemas for `apps_list`, `apps_search`, `apps_get_details`, and `webhooks_verify_signature` now admit the canonical error shape without changing their successful result fields.

### Fixed

- Normalize direct worker errors and converted thrown errors at the central `WorkerManager` transport boundary so all 390 tools return consistent machine-readable failures.
- Redact sensitive error values before transport while preserving semantic identifiers and stable redaction markers across repeated normalization.
- Return canonical structured errors from the three `apps_get_metadata` no-version, missing-state, and missing-localization paths instead of embedding an entire JSON object inside the `error` string.

### Compatibility

- No public MCP tool or input was added, removed, or renamed; successful tool results remain unchanged.
- Error results retain their first human-readable text block and may now include an additional compact JSON text mirror plus `structuredContent`; clients assuming exactly one error content block should select the first human block or consume `structuredContent`.
- The strict contract pin remains unchanged at 2,154 optional Apple inputs: 730 bound, 6 internally controlled, 1,010 intentionally omitted, and 408 still queued for domain review.

## [3.6.0] - 2026-07-20

### Changed

- `subscriptions_pricing_summary` now keeps Apple's `MONTHLY` and `UPFRONT` schedules separate, with an optional `plan_type` filter and complete per-plan summaries.
- Pricing summaries traverse all Apple pages by default, accept a bounded 1...200 page `limit`, and support an optional 1...100 `max_pages` cap with explicit continuation metadata.
- Complete summaries expose every effective, scheduled, and undated price in stable order while retaining the existing top-level compatibility fields for an unambiguous single plan.

### Fixed

- Reject malformed pricing-summary inputs, scope-changing continuation URLs, invalid Apple resource linkage, repeated pagination links, and conflicting duplicate price resources before returning a misleading aggregate.
- Preserve an undated Apple starting price as the current price when no dated effective price exists.
- Stop treating partial continuation segments or mixed plan types as a complete legacy current-price summary.

### Compatibility

- No public MCP tool or required input was added, removed, or renamed; `plan_type`, `limit`, `max_pages`, and `next_url` are optional additions to `subscriptions_pricing_summary`.
- Existing `current_price` and `scheduled_prices` fields remain available, but are intentionally null or empty when traversal is partial or multiple plan types make a single legacy summary ambiguous; use `plan_summaries` in those cases.
- The strict contract pin records 2,154 optional Apple inputs: 730 bound, 6 internally controlled, 1,010 intentionally omitted, and 408 still queued for domain review.

## [3.5.0] - 2026-07-20

### Changed

- Review-attachment reads now request a stable Apple 4.4.1 projection that includes file metadata, delivery state, and review-detail relationship linkage without returning upload operations.
- `review_attachments_get` and `review_attachments_list` now return `appStoreReviewDetailId`; collection results also return Apple's paging `total` when available.
- `review_attachments_list` now publishes a bounded 1...200 limit contract and requires non-default limits to be repeated with `next_url` so continuation requests preserve their original page size and projection.

### Fixed

- Reject review-attachment continuation URLs that change the parent review detail, fixed sparse-field projection, or effective page limit before making a network request.
- Use the same safe sparse-field projection while reconciling a committed upload, avoiding unnecessary presigned upload-operation data during delivery checks.
- Describe upload input as a generic attachment file instead of incorrectly limiting it to images.

### Compatibility

- No public MCP tool or input was added, removed, or renamed; existing review-attachment calls remain valid.
- Clients continuing a list started with a non-default `limit` must pass that same `limit` together with Apple's returned `next_url`.
- The strict contract pin records 2,154 optional Apple inputs: 724 bound, 6 internally controlled, 1,012 intentionally omitted, and 412 still queued for domain review.

## [3.4.0] - 2026-07-20

### Changed

- `apps_search` now exhausts every Apple result page for both exact-name and Bundle ID filters instead of returning only the first page from each branch.
- Search requests use a fixed 200-item page size, the required App projection, and Apple-side name/Bundle ID/SKU ordering; merged results are de-duplicated by App ID and returned in deterministic order.
- Search results now report `pagesFetched` so clients can see how many Apple pages were combined.

### Fixed

- Reject blank search queries before network access.
- Reject off-origin, cross-route, filter-changing, projection-changing, or otherwise scope-drifting continuation URLs instead of returning a partial or mixed search result.
- Detect repeated Apple continuation URLs and fail explicitly instead of looping indefinitely.
- Reviewed and classified 62 previously unclassified optional Apple inputs associated with the two search invocations.

### Compatibility

- No public MCP tool or input was added, removed, or renamed; existing `apps_search.query` calls remain valid.
- Search results can now contain Apps that were previously hidden beyond Apple's first page, and their ordering is now stable rather than dependent on `Set` iteration.
- The strict contract pin records 2,154 optional Apple inputs: 721 bound, 6 internally controlled, 1,012 intentionally omitted, and 415 still queued for domain review.

## [3.3.0] - 2026-07-20

### Changed

- Hardened all 10 Beta App tools against App Store Connect API 4.4.1 with fixed sparse-field projections, deterministic page scopes, effective limits, resource links, paging totals, and Build relationship lineage.
- `beta_app_list_submissions` now accepts one or multiple Build IDs and review states while preserving the existing scalar call shape; submission reads include the matching Build projection when Apple provides it.
- Beta review-detail updates now preserve omission, explicit values, and explicit `null` independently for every writable field.

### Fixed

- Reject malformed Beta App localization and review-detail attributes, empty updates, invalid limits, and unsupported review states before network access.
- Prevent continuation URLs from dropping or changing Build filters, fixed includes, sparse fields, or the effective page limit.
- Redact a returned demo-account password only when Apple actually supplied one; an absent password remains absent instead of being invented in the MCP result.
- Preserve an unambiguous submission-to-Build ID from Apple relationship data, an included Build, the create request, or a single Build filter, while leaving ambiguous linkage explicitly null.

### Compatibility

- No public MCP tool was added, removed, or renamed; the server still exposes 390 tools.
- Existing scalar `build_id` and `review_state` calls remain valid alongside the new array form.
- Localization fields cannot be cleared after they are set according to Apple's contract, so explicit `null` is rejected locally for those fields; nullable review-detail fields support explicit clearing.
- The strict contract pin records 2,154 optional Apple inputs: 715 bound, 6 internally controlled, 956 intentionally omitted, and 477 still queued for domain review.

## [3.2.0] - 2026-07-20

### Added

- Added `app_versions_delete_phased_release` for removing an App Store phased-release configuration, bringing the public surface to 390 tools without removing an existing tool.
- Added schema-v2 accounting for optional Apple query and request-body inputs, including exact reviewed classifications and a strict count-and-identity coverage pin that blocks silent regressions during phased remediation.
- Added contract and MCP regression coverage across metadata, app lifecycle, analytics, reviews, metrics, provisioning, pricing, TestFlight, commerce, marketing, webhooks, and Xcode Cloud workflows.

### Changed

- Hardened Apps and App Store version workflows against Apple 4.4.1 with current states and platforms, ownership validation, deterministic pagination, nullable metadata updates, included relationships, and complete media traversal.
- Aligned TestFlight administration, beta feedback, build processing, pre-release versions, and Xcode Cloud request and response contracts with the mapped Apple operations.
- Corrected IAP, subscription, offer-code, price-schedule, and territory-availability workflows, including inline manual prices, relationship pagination, truncation metadata, environment-aware one-time codes, and lossless CSV values.
- Expanded analytics, reviews, users, webhooks, metrics, provisioning, App Info, accessibility, and App Events with Apple's current filters, includes, limits, relationships, and response fields.
- Corrected custom product page templates, screenshot and preview parent relationships, promoted-purchase targeting, and Product Page Optimization projections including visionOS.

### Fixed

- Preserved omission, explicit values, and explicit `null` across supported nullable updates while rejecting malformed and no-op writes before network access.
- Corrected customer-review response lookup so a relationship `404` is reported as no response only after the parent review is confirmed to exist.
- Prevented app/version ownership mismatches, pagination-scope drift, incomplete metadata selection, and swallowed screenshot or preview errors.
- Corrected subscription and IAP one-time-code endpoints and media types, Xcode Cloud provider and test-result projections, webhook signature output nullability, custom-page state projection, and sandbox-tester relationship typing.
- Fixed Swift 6 compilation regressions in the Apps and IAP contract handlers and made encoded-path regression coverage portable across the release toolchain.

### Compatibility

- No public MCP tool was removed. Several list and metrics filters now accept either one value or an array; existing scalar calls remain valid.
- `app_versions_list.states` remains available as a deprecated compatibility filter; use `app_version_states` for Apple's current `appVersionState`.
- One-time-code values now return Apple's non-paginated CSV losslessly through `values_csv`, `media_type`, and `byte_count`; unsupported pagination inputs are no longer exposed.
- `app_events_create` and `app_events_update` now require an absolute `deep_link` and accept only Apple's documented purchase-requirement values.
- IAP types follow Apple's current `CONSUMABLE`, `NON_CONSUMABLE`, and `NON_RENEWING_SUBSCRIPTION` values; auto-renewable products belong to the subscription tools.
- Unsupported App Event values, noncanonical IAP types, ambiguous Xcode Cloud run selectors, ambiguous promoted-purchase product targets, malformed arrays, and empty updates now fail locally instead of issuing an invalid Apple request.
- The strict contract pin currently records 2,154 optional Apple inputs: 706 bound, 6 internally controlled, 965 intentionally omitted, and 477 still queued for domain review. Future phases must update this pin explicitly and cannot increase the unreviewed surface silently.
- The manifest maps 365 Apple operations; 382 tools remain `partial` for full type, enum, or response completeness, and 8 deprecated tools remain registered with migration guidance.

## [3.1.0] - 2026-07-20

### Added

- Added a credential-free `openapi-contract-check` command and bundled semantic manifest pinned to Apple App Store Connect API 4.4.1. The gate models all 389 public tools, maps 363 Apple operations, defers 537, scopes out 363, and explicitly accounts for all 1,263 Apple operations.
- Added credential-free `--version` and `--help` commands.

### Changed

- Aligned app version lifecycle, TestFlight, review details, age ratings, pricing, Product Page Optimization, users, subscriptions and offers, reviews, analytics, and asset workflows with Apple App Store Connect API 4.4.1.
- Made company switching atomic across concurrent MCP calls so a request cannot observe credentials and workers from different companies; empty or ambiguous company queries are now rejected.
- Reworked screenshot, preview, in-app purchase, subscription, and review-attachment uploads around immutable file snapshots, bounded-memory file transfer, pre-commit rollback, ambiguous-commit reconciliation, and delivery-state verification.
- Hardened sales and financial report parsing with strict Apple report combinations, exact decimal aggregation, bounded gzip decoding, and bounded TSV scanning and materialization.
- Strengthened CI with immutable action revisions, exact annotated-tag provenance checks, warning-clean release builds, strict contract checks, and relocated-binary resource verification.

### Fixed

- Bound every `next_url` request to its original App Store Connect origin, collection path, and required query parameters.
- Validated cached JWT header, signature, issuer, audience, key ID, issue time, lifetime, and expiry before reuse.
- Corrected Apple request fields, enums, relationships, response projections, nullable update semantics, and report versions found during the App Store Connect 4.4.1 audit.
- Preserved actionable resource identifiers and cleanup guidance when upload reservation, transfer, commit, reconciliation, or processing cannot be confirmed.

### Security

- `webhooks_create` and `webhooks_update` now require a non-repeating, sufficiently diverse secret of at least 32 characters and never return it.
- Webhook callback URLs now require HTTPS and reject credentials, fragments, missing hosts, and malformed ports before any App Store Connect request is sent.
- Resource identifiers are encoded as single URL path segments, and the HTTP client rejects non-canonical, traversal-capable, query-bearing, or fragment-bearing API endpoints before network access.
- Signed Apple upload URLs and request headers are no longer exposed in MCP text, structured results, or transport-failure diagnostics.
- Gzip reports now enforce header, trailer, CRC32, decompressed-size, trailing-data, row, column, scanned-cell, and retained-cell limits before returning results.

### Deprecated

- Promoted-purchase image tools remain registered for compatibility but now return structured migration guidance because Apple removed their backing endpoints in App Store Connect API 4.4.1.
- `subscriptions_get_availability`, `subscriptions_set_availability`, `subscriptions_list_available_territories`, and `subscriptions_inventory` remain registered for compatibility, but Apple 4.4.1 deprecates their legacy `subscriptionAvailability` resource in favor of plan-type-aware `subscriptionPlanAvailabilities`. The inventory helper can omit subscriptions beyond the first included relationship page and must not be treated as an authoritative complete inventory.

### Compatibility

- All 389 public tool names remain registered, but security and contract fixes intentionally reject weak webhook secrets, non-HTTPS webhook callbacks, unsafe or pre-encoded resource-ID path segments, unsafe or route-mismatched pagination URLs, and unsupported legacy review-attachment input. Pass raw App Store Connect IDs; the MCP now encodes each ID exactly once.
- Signed upload URLs and headers are intentionally omitted from asset results. Confirmed uploads that Apple is still processing return a non-error pending state with inspection guidance instead of encouraging a duplicate upload.
- `builds_update_beta_detail` no longer accepts Apple's read-only `internal_build_state` or `external_build_state` fields.
- `builds_set_beta_localization` now accepts only build-localization fields; move app-level contact and policy metadata to the corresponding `beta_app_*_localization` tools.
- Replace `app_versions_set_review_details.attachment_file_id` with a separate `review_attachments_upload` call.
- Subscription offer creators now require the Apple 4.4.1 inputs appropriate to each mode, including `territory_ids`, `customer_eligibilities`, or `price_point_ids` where documented by the tool schema.

## [3.0.2] - 2026-06-03

### Fixed

- Metadata auto-selection now prefers `PREPARE_FOR_SUBMISSION`, `REJECTED`, and `METADATA_REJECTED` versions before `READY_FOR_SALE`.
- Added current Apple app-version and external-beta states to the public tool schemas.

### Changed

- Refreshed installation examples, architecture documentation, and worker/tool counts for the 389-tool v3 surface.

## [3.0.1] - 2026-06-03

### Fixed

- `apps_update_metadata` no longer rejects `REJECTED` or `METADATA_REJECTED` versions locally; App Store Connect remains the source of truth for editable-state validation.
- Added regression coverage for rejected-version updates and Apple-side state errors.

## [3.0.0] - 2026-05-29

### Breaking Changes

- Consolidated subscription offer-code, introductory-offer, promotional-offer, and win-back-offer tools under the public `subscriptions_*` namespace. The former standalone worker prefixes are no longer registered.

### Added

- Added the v3 commerce surface for subscription and one-time in-app purchase discovery, pricing, availability, offers, assets, promoted purchases, inventory, and territory-aware price reads.

### Security

- Extended `--read-only` enforcement to the v3 mutation tools before handler execution.

### Changed

- Updated the public surface to 389 tools across 32 worker filter domains and aligned it with Apple App Store Connect API 4.3.1.

## [2.5.0] - 2026-05-20

### Fixed

- Webhook tools (`webhooks_verify_signature`, `webhooks_parse_payload`, `webhooks_triage_event`) no longer emit a top-level `anyOf` in their input schema. The Anthropic API rejects top-level `oneOf`/`anyOf`/`allOf` in a tool `input_schema`, which had caused every Claude Code sub-agent (Explore, Plan, teammates) to fail with HTTP 400 since 2.4.0. The "payload or payload_base64" constraint is still enforced at runtime in the handlers, and `ToolMetadataPolicy` now strips top-level composition keywords as a safety net.
- `company_switch` is now transactional and rolls back on failed worker reinitialization, preventing a split-brain state where `company_current` and the active API workers disagree (P1-01).
- `app_versions_submit_for_review` surfaces `submission_id` and partial-failure context when a later step fails, so a created review submission can still be cancelled or inspected (P1-02).
- `app_versions_release` performs a preflight version-state check and requires explicit confirmation before the irreversible release request (P2-02).
- App Store Connect `X-Rate-Limit` header is parsed per Apple's documented format (with legacy header fallback), and `Retry-After` now supports HTTP-date values in addition to numeric seconds (P2-01, P3-01).
- Demo-account passwords and secret-like keys are redacted from MCP results (P2-03).
- Pagination host allowlist now follows the configured base URL instead of hardcoding the Apple host (P2-04).

### Changed

- Clearer diagnostics for missing, unreadable, malformed, or empty `companies.json` (P3-02).

## [2.4.0] - 2026-05-08

### Added

- Local webhook receiver helpers: `webhooks_verify_signature`, `webhooks_parse_payload`, and `webhooks_triage_event` for HMAC validation, payload normalization, and actionable event/delivery triage without calling App Store Connect.

### Changed

- README worker counts, webhook tool docs, and coverage matrix now reflect 348 tools across 36 worker domains.

## [2.3.0] - 2026-05-08

### Added

- Accessibility declaration tools (`accessibility_*`) for listing, reading, creating, updating/publishing, deleting, and relationship-only listing of App Store accessibility declarations by device family.

### Changed

- README worker counts, worker filtering docs, and coverage matrix now reflect 345 tools across 36 worker domains.

## [2.2.0] - 2026-05-07

### Added

- OpenAPI coverage tooling via `asc-mcp openapi-coverage`, using Apple's official App Store Connect OpenAPI JSON without loading ASC credentials or starting the MCP server.
- Generated `ASC-OPENAPI-COVERAGE-GENERATED.md` report for Apple App Store Connect API 4.3 with domain-level path/operation counts and drift triage.

### Changed

- CI now smoke-tests the OpenAPI coverage command against a local fixture.
- Coverage inventory now marks automated OpenAPI drift reporting as implemented.

## [2.1.0] - 2026-05-05

### Added

- MCP 2025-11-25 tool metadata policy for all 339 tools: standard annotations plus `anthropic/maxResultSizeChars`.
- Webhook notification tools for listing, reading, creating, updating, deleting, delivery inspection, redelivery, and ping testing.
- TestFlight beta feedback tools for crash submissions, screenshot submissions, crash log reads, and cleanup.
- Xcode Cloud tools for products, workflows, build runs, actions, artifacts, issues, test results, Xcode/macOS versions, SCM providers, repositories, git references, pull requests, and starting builds.
- `--read-only` runtime mode that blocks App Store Connect mutation tools before handler execution.
- App Store Connect API coverage matrix for Apple 4.0+ documentation gaps and future worker planning.
- Structured JSON results for JSON-producing handlers, with `outputSchema` on stable auth, company, apps, and selected analytics tools.
- Structured App Store Connect error decoding and safe rate-limit metadata capture.
- Metadata validation before key ASC mutations: locale, emoji, URL, and length checks.
- HTTP and upload service tests, MCP result builder tests, metadata policy tests, and docs drift coverage.

### Changed

- Migrated deprecated MCP SDK `.text(...)` usage to current `Tool.Content.text(text:annotations:_meta:)` helpers.
- Refactored `WorkerManager` routing into ordered descriptors for overlapping prefixes.
- Refactored uploads to stream chunks from disk with bounded concurrency and streaming MD5.
- Updated SwiftPM to Swift tools 6.2 and Swift language mode v6.
- Release build is now warning-clean.

### Security

- Redacts sensitive identifiers and private-key paths in runtime diagnostic output.
- Keeps ASC verification read-only for production smoke checks.

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
