# ТЗ 1. Расширение покрытия App Store Connect API

Дата: 2026-05-05

## 1. Цель

Подготовить следующую additive-версию `asc-mcp`, которая закрывает важные пробелы в покрытии App Store Connect API и добавляет пользователям новые полезные методы без переименования существующих tools.

Рекомендуемый SemVer:
- `2.2.0`, если добавляем только новые worker/tools, модели, docs и тесты.
- `3.0.0`, только если будет принято отдельное решение менять существующие tool names или wire-contract.

## 2. Current State

Сейчас сервер уже покрывает 293 tools в 32 worker domains:
- apps, metadata, localizations;
- builds, processing, TestFlight beta details;
- app versions, review submission, release, phased rollout;
- customer reviews and responses;
- beta groups/testers;
- IAP, subscriptions, offer codes, win-back, intro/promotional offers;
- provisioning: bundle IDs, devices, certificates, profiles, capabilities;
- pricing, users, app events;
- sales/finance/analytics reports;
- screenshots, app previews, custom product pages, PPO, promoted purchases;
- review attachments, metrics/diagnostics.

Главный gap: сервер хорошо покрывает classic release/monetization workflow, но почти не покрывает новые и специализированные зоны Apple API: webhooks, TestFlight feedback, accessibility declarations, background assets, App Clips, Xcode Cloud, Game Center, Alternative Distribution, merchant/pass IDs, app tags, routing coverage.

## 3. Official Documentation Baseline

Использовать только официальные источники как source of truth:
- App Store Connect API overview: https://developer.apple.com/documentation/appstoreconnectapi
- App Store Connect API release notes: https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-release-notes
- API 4.0 release notes: https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-0-release-notes
- Webhook notifications: https://developer.apple.com/documentation/appstoreconnectapi/webhook-notifications
- TestFlight prerelease/beta: https://developer.apple.com/documentation/appstoreconnectapi/prerelease-versions-and-beta-testers
- Beta feedback crash submissions: https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-crash-submissions
- Beta feedback screenshot submissions: https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-screenshot-submissions
- Accessibility declarations: https://developer.apple.com/documentation/appstoreconnectapi/accessibility-declarations
- Background assets: https://developer.apple.com/documentation/appstoreconnectapi/background-assets
- App Clips: https://developer.apple.com/documentation/appstoreconnectapi/app-clips
- Xcode Cloud workflows/builds: https://developer.apple.com/documentation/appstoreconnectapi/xcode-cloud-workflows-and-builds
- Game Center: https://developer.apple.com/documentation/appstoreconnectapi/game-center
- Alternative marketplaces/web distribution: https://developer.apple.com/documentation/appstoreconnectapi/alternative-marketplaces-and-web-distribution
- Merchant IDs: https://developer.apple.com/documentation/appstoreconnectapi/merchantids
- Pass type IDs: https://developer.apple.com/documentation/appstoreconnectapi/pass-type-id
- App tags: https://developer.apple.com/documentation/appstoreconnectapi/app-tags
- Routing app coverages: https://developer.apple.com/documentation/appstoreconnectapi/routing-app-coverages
- App categories: https://developer.apple.com/documentation/appstoreconnectapi/app-categories
- Customer reviews: https://developer.apple.com/documentation/appstoreconnectapi/customer-reviews

Дополнительно обязательно скачать и распарсить official OpenAPI specification из App Store Connect API overview. Итоговая coverage matrix должна строиться не вручную, а из OpenAPI endpoint inventory.

## 4. Scope

### In Scope

- Static coverage audit against Apple OpenAPI spec.
- Новые additive worker domains and tools.
- Read-only live smoke только для безопасных read endpoints.
- Tool annotations/outputSchema/structuredContent для новых tools по текущему MCP policy.
- Validation для всех write tools до отправки запроса в ASC.
- Docs, tests, CI drift checks.

### Out of Scope

- Переименование существующих tools.
- Удаление или изменение runtime behavior существующих tools.
- Live write/mutation в verification.
- Автоматическое включение всех новых heavy workers в user workflows без `--workers` guidance.

## 5. Required Discovery Work

### 5.1 OpenAPI Coverage Matrix

Добавить скрипт или тестовый helper:
- скачать/прочитать Apple OpenAPI spec;
- нормализовать endpoint list: method, path, resource family, operationId, tags;
- собрать current tools из `getTools()`;
- вручную или semi-automated сопоставить endpoint -> tool;
- вывести таблицу:
  - covered;
  - partially covered;
  - missing;
  - intentionally not supported;
  - deprecated/removed.

Acceptance:
- `docs/ASC-COVERAGE-MATRIX-2026-05-05.md` или generated artifact содержит все endpoint families.
- README получает короткий coverage summary, не полный OpenAPI dump.
- CI имеет drift test: если tool count/worker count меняется, docs должны обновиться.

## 6. Priority Backlog

### P0. WebhooksWorker

Why:
Webhooks дают real-time события: app version state, TestFlight feedback, beta/build changes. Это сильно полезнее polling для release-monitoring и TestFlight feedback triage.

Docs:
https://developer.apple.com/documentation/appstoreconnectapi/webhook-notifications

Proposed worker:
- `webhooks_list_for_app(app_id, limit?, next_url?)`
- `webhooks_get(webhook_id)`
- `webhooks_create(app_id, url, event_types, name?, enabled?)`
- `webhooks_update(webhook_id, url?, event_types?, name?, enabled?)`
- `webhooks_delete(webhook_id)`
- `webhooks_list_deliveries(webhook_id, limit?, next_url?)`
- `webhooks_redeliver(delivery_id)` or `webhooks_create_delivery(...)` after exact OpenAPI semantics check
- `webhooks_ping(webhook_id)` or `webhooks_create_ping(...)` after exact OpenAPI semantics check

Validation:
- URL must be absolute HTTPS by default; HTTP only behind explicit `allow_insecure_url: true` if Apple permits it.
- Event types must be enum-backed from `WebhookEventType`.
- Delete/update/ping/redeliver marked non-read-only with correct destructive/idempotent hints.

Tests:
- Tool count/name tests.
- Parameter validation.
- URL validation.
- Output schema for list/get/create/update.
- Read-only smoke: list webhooks for one app only.

### P0. BetaFeedbackWorker

Why:
TestFlight feedback screenshots/crash logs are operationally valuable and currently missed. Users can triage beta issues without opening App Store Connect UI.

Docs:
- https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-crash-submissions
- https://developer.apple.com/documentation/appstoreconnectapi/beta-feedback-screenshot-submissions

Proposed tools:
- `beta_feedback_list_crashes(app_id, limit?, filters?, next_url?)`
- `beta_feedback_get_crash(submission_id)`
- `beta_feedback_get_crash_log(submission_id or crash_log_id)`
- `beta_feedback_delete_crash(submission_id)`
- `beta_feedback_list_screenshots(app_id, limit?, filters?, next_url?)`
- `beta_feedback_get_screenshot(submission_id)`
- `beta_feedback_delete_screenshot(submission_id)`

Nice-to-have:
- `beta_feedback_summary(app_id, days?, build_version?, platform?)` as local aggregation from read endpoints.

Validation:
- Delete tools must be destructive.
- Crash logs/screenshots may contain PII; redact user-identifying fields in summaries unless explicitly requested.
- Heavy log/screenshot outputs should use resource links or file output paths if MCP SDK supports resources later.

### P0. AccessibilityDeclarationsWorker

Why:
API 4.0 added accessibility declarations. This is user-facing App Store metadata and increasingly important for product quality and compliance.

Docs:
https://developer.apple.com/documentation/appstoreconnectapi/accessibility-declarations

Proposed tools:
- `accessibility_list(app_id, limit?, next_url?)`
- `accessibility_get(declaration_id)`
- `accessibility_create(app_id, device_family, supports_vision?, supports_hearing?, supports_mobility?, supports_cognitive?, supports_speech?, details?)`
- `accessibility_update(declaration_id, ...)`
- `accessibility_delete(declaration_id)`
- `accessibility_update_app_url(app_id, accessibility_url)`

Validation:
- Device family enum.
- Accessibility URL must be absolute HTTPS.
- Field-level validation from exact Apple schema.

### P1. BackgroundAssetsWorker

Why:
Apple-hosted background assets are a newer distribution surface for asset packs independently of main app version. Useful for games/content apps.

Docs:
https://developer.apple.com/documentation/appstoreconnectapi/background-assets

Proposed tools:
- `background_assets_list(app_id, limit?, next_url?)`
- `background_assets_get(asset_id)`
- `background_assets_create(app_id, name?, ...exact schema)`
- `background_assets_list_versions(asset_id, limit?, next_url?)`
- `background_assets_create_version(asset_id, version_string?, ...exact schema)`
- `background_assets_get_version(version_id)`
- `background_assets_list_upload_files(version_id)`
- `background_assets_upload_file(version_id, file_path, checksum_algorithm?)`
- `background_assets_get_app_store_release(release_id)`
- `background_assets_get_internal_beta_release(release_id)`
- `background_assets_get_external_beta_release(release_id)`

Implementation:
- Reuse `UploadService` if upload operation format matches `DeliveryFileUploadOperation`.
- Add checksum algorithm support beyond MD5 if Apple requires it for this resource.

### P1. RoutingAppCoverageWorker

Why:
Routing apps need geographic coverage files before review. Existing generic upload foundation can support this well.

Docs:
https://developer.apple.com/documentation/appstoreconnectapi/routing-app-coverages

Proposed tools:
- `routing_coverage_get_for_version(version_id)`
- `routing_coverage_get(coverage_id)`
- `routing_coverage_upload(version_id, file_path)`
- `routing_coverage_replace(coverage_id, file_path)`
- `routing_coverage_delete(coverage_id)`

Validation:
- File must exist, be below Apple max size after exact doc check, and use supported format.
- Upload is mutation/high-risk but not destructive unless replacing/deleting.

### P1. AppTagsWorker

Why:
Apple-created app tags affect product page/category perception. API lets teams read tags and remove irrelevant tags.

Docs:
https://developer.apple.com/documentation/appstoreconnectapi/app-tags

Proposed tools:
- `app_tags_list(app_id, limit?, next_url?)`
- `app_tags_get_territories(tag_id, limit?, next_url?)`
- `app_tags_update(tag_id, is_disabled? or exact schema field)`

Validation:
- Exact update schema from OpenAPI.
- Mark update as state-changing.

### P1. AppClipsWorker + BetaAppClipsWorker

Why:
App Clips and beta App Clip invocations are part of ASC/TestFlight automation and are currently absent.

Docs:
- https://developer.apple.com/documentation/appstoreconnectapi/app-clips
- TestFlight docs list `beta-app-clip-invocations` and localizations.

Proposed tools:
- `app_clips_get(app_clip_id)`
- `app_clips_list_default_experiences(app_clip_id)`
- `app_clips_list_advanced_experiences(app_clip_id)`
- `app_clips_get_advanced_experience(experience_id)`
- `app_clips_create_advanced_experience(...)`
- `app_clips_update_advanced_experience(...)`
- `app_clips_delete_advanced_experience(experience_id)`
- `beta_app_clips_list_invocations(app_id or app_clip_id, ...)`
- `beta_app_clips_create_invocation(...)`
- `beta_app_clips_update_invocation(...)`
- `beta_app_clips_delete_invocation(...)`
- localization list/create/update/delete for beta invocations.

### P1. Provisioning Extensions: Merchant IDs and Pass Type IDs

Why:
Provisioning currently covers core bundle/device/cert/profile flows but misses Apple Pay merchant IDs and Wallet pass type IDs.

Docs:
- https://developer.apple.com/documentation/appstoreconnectapi/merchantids
- https://developer.apple.com/documentation/appstoreconnectapi/pass-type-id

Proposed tools:
- `merchant_ids_list`, `merchant_ids_get`, `merchant_ids_create`, `merchant_ids_update`, `merchant_ids_delete`, `merchant_ids_list_certificates`
- `pass_type_ids_list`, `pass_type_ids_get`, `pass_type_ids_create`, `pass_type_ids_update`, `pass_type_ids_delete`, `pass_type_ids_list_certificates`

Integration:
- Either extend `ProvisioningWorker` or add two focused workers. Prefer focused workers to avoid ProvisioningWorker becoming too large.

### P2. XcodeCloudWorker

Why:
This is high value for teams using Xcode Cloud, but large in scope and partly unrelated to App Store release mutation. Add behind worker filter.

Docs:
https://developer.apple.com/documentation/appstoreconnectapi/xcode-cloud-workflows-and-builds

Phase 1 read-only tools:
- `xcode_cloud_list_products`
- `xcode_cloud_list_workflows(product_id)`
- `xcode_cloud_get_workflow(workflow_id)`
- `xcode_cloud_list_build_runs(workflow_id or product_id)`
- `xcode_cloud_get_build_run(build_run_id)`
- `xcode_cloud_list_build_actions(build_run_id)`
- `xcode_cloud_list_artifacts(build_run_id)`
- `xcode_cloud_list_issues(build_run_id)`
- `xcode_cloud_list_test_results(build_run_id)`
- `xcode_cloud_list_xcode_versions`
- `xcode_cloud_list_macos_versions`
- SCM read tools: providers/repositories/pull_requests/git_references.

Phase 2 mutation tools:
- start build run;
- create/update/delete workflows.

Safety:
- Mutating CI workflows should require explicit `dry_run=false` and strong destructive annotations.

### P2. GameCenterWorker

Why:
Huge domain, very useful for game apps, not useful for most non-game apps. Must be opt-in.

Docs:
https://developer.apple.com/documentation/appstoreconnectapi/game-center

Phase 1:
- Details/groups read and enablement.
- Achievements list/get/create/update/localizations/images.
- Leaderboards list/get/create/update/localizations/images.

Phase 2:
- Leaderboard sets, versions, releases.
- Challenges and activities.

Phase 3:
- Matchmaking rules, expressions, rule sets, queues, teams, testing, metrics.

Guideline:
- Do not add all Game Center tools at once if it pushes default tool count too high. Add `--workers game_center_core`, `game_center_assets`, `game_center_matchmaking` or one `game_center` worker disabled in recommended presets.

### P2. AlternativeDistributionWorker

Why:
Important for EU alternative marketplaces/web distribution, but sensitive and not relevant to every team.

Docs:
https://developer.apple.com/documentation/appstoreconnectapi/alternative-marketplaces-and-web-distribution

Proposed read-first tools:
- `alt_distribution_list_keys`, `alt_distribution_get_key`
- `alt_distribution_list_domains`, `alt_distribution_get_domain`
- `alt_distribution_list_packages(app_id, ...)`
- `alt_distribution_get_package(package_id)`
- `alt_distribution_list_notifications(...)`
- `marketplace_search_list_configurations`, `marketplace_search_get_configuration`

Mutation phase:
- create/update/delete keys/domains/search configs only after exact role/security review.

Safety:
- Keep worker opt-in.
- Redact package URLs/tokens if Apple returns signed URLs.

### P2. App Store Metadata Refinements

Potential additions:
- `app_categories_list`, `app_categories_get`, `app_categories_list_subcategories`.
- `app_info_update_categories` helper that validates category IDs before mutation.
- Complete age-rating declaration model drift against latest 4.0 removals.
- App tag and accessibility URL integration into app metadata workflows.
- Customer review summarization already exists as `reviews_summarizations`; add outputSchema and docs examples if missing.

Docs:
- https://developer.apple.com/documentation/appstoreconnectapi/app-categories
- https://developer.apple.com/documentation/appstoreconnectapi/customer-reviews

### P3. Long Tail / Verify Against OpenAPI

Review after OpenAPI coverage matrix:
- Promo codes for app/IAP if separate endpoints exist outside subscription offer codes.
- App bundles.
- Pre-orders, app availability v2 gaps.
- Additional relationship endpoints where they improve workflow and avoid manual ID discovery.
- Deprecated endpoints that should be documented as intentionally unsupported.

## 7. Implementation Requirements

### 7.1 Worker Pattern

For each new worker:
- `Worker.swift`
- `Worker+ToolDefinitions.swift`
- `Worker+Handlers.swift`
- Models in `Models/<Domain>/`
- Registration in `WorkerManager`
- `validWorkers` in `EntryPoint`
- README worker table and tool sections
- Tests:
  - tool count/name;
  - routing unknown tool;
  - parameter validation;
  - metadata policy;
  - docs drift.

### 7.2 MCP Requirements

Every new tool must include:
- stable name, no existing names changed;
- JSON Schema input;
- `ToolMetadataPolicy` classification;
- `_meta["anthropic/maxResultSizeChars"]`;
- outputSchema for stable custom summary objects;
- `structuredContent` for JSON results;
- text JSON fallback for compatibility.

### 7.3 Validation Requirements

For every mutation:
- validate required IDs and enum values;
- validate URLs;
- validate file existence/ranges/checksums for upload-like tools;
- validate metadata text length/emoji when relevant;
- return `isError: true` with structured field errors before ASC call.

### 7.4 Safety Requirements

- No live mutation in tests.
- Delete/revoke/release/submit/clear tools must be destructive.
- Upload/create/update must be non-read-only.
- Read-only tools must be idempotent where true.
- Outputs containing feedback/crash/review data must avoid accidental PII leakage in summaries.

## 8. Verification Plan

Local:
- `swift package show-dependencies --format json`
- `swift build`
- `swift build -c release`
- release warning scan
- `swift test`
- `git diff --check`

Static:
- OpenAPI coverage matrix generated.
- No direct deprecated MCP `.text(...)` usage.
- All new tools have annotations/_meta.
- README counts match `getTools()`.

Live read-only smoke:
- Existing: `auth_generate_token`, `auth_token_status`, `apps_list limit=1`.
- New read-only examples after reload:
  - `webhooks_list_for_app app_id=<known app>`
  - `beta_feedback_list_crashes app_id=<known app> limit=1`
  - `accessibility_list app_id=<known app>`
  - Do not call create/update/delete/upload/ping/redeliver unless user explicitly approves.

## 9. Acceptance Criteria

- Coverage matrix identifies all Apple endpoint families and marks current state.
- New P0 workers implemented and tested.
- At least one P1 worker implemented, or P1 backlog explicitly deferred with evidence.
- Existing 293 tools remain backward compatible.
- New tool count and worker count are reflected in README and tests.
- `swift build`, release build, `swift test`, `git diff --check` pass.
- Release build has zero warnings.
- No ASC mutations are executed in verification.

## 10. Recommended Delivery Order

1. OpenAPI coverage matrix generator.
2. WebhooksWorker.
3. BetaFeedbackWorker.
4. AccessibilityDeclarationsWorker.
5. RoutingAppCoverageWorker.
6. BackgroundAssetsWorker.
7. AppClips/BetaAppClips.
8. Merchant/Pass type IDs.
9. XcodeCloudWorker read-only.
10. GameCenterWorker opt-in phases.
11. AlternativeDistributionWorker opt-in phases.
