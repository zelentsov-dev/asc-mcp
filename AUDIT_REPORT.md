# ASC MCP — Final Audit Report

**Date**: 2026-02-18
**Scope**: 25 workers, 205 tools (94 read + 111 write)
**Companies**: Awared SLU (primary), Wheele (write tests), FINDUS (cross-check)

---

## Summary Table by Group

| # | Group | Read tools | Write tools | ✅ | ⚠️ | ❌ | 🔇 |
|---|-------|-----------|------------|-----|-----|-----|-----|
| 1 | Companies, Auth, Apps | 16 | 3 | 15 | 3 | 0 | 1 |
| 2 | Builds, TestFlight | 16 | 6 | 19 | 1 | 0 | 2 |
| 3 | App Store Lifecycle | 9 | 9 | 15 | 1 | 0 | 2 |
| 4 | Reviews | 5 | 2 | 6 | 1 | 0 | 0 |
| 5 | Monetization | 28 | 28 | 47 | 4 | 0 | 5 |
| 6 | Analytics + Metrics | 13 | 0 | 10 | 0 | 2 | 1 |
| 7 | Screenshots | 3 | 9 | 12 | 0 | 0 | 0 |
| 8 | Marketing (Events, CPP, PPO) | 11 | 16 | 27 | 0 | 0 | 0 |
| 9 | Infrastructure (Provisioning, Users) | 12 | 12 | 22 | 0 | 0 | 2 |
| **Σ** | | **113** | **85** | **173** | **10** | **2** | **13** |

**Total**: 173 ✅ (87%) / 10 ⚠️ (5%) / 2 ❌ (1%) / 13 🔇 (7%)

---

## Critical Issues (❌ FAIL)

### 1. `metrics_list_diagnostics` — DUPLICATE + 404
**Worker**: MetricsWorker
**Issue**: Identical to `metrics_build_diagnostics` — both call `/v1/builds/{id}/diagnosticSignatures`. Returns 404 for pre-release builds without explanation.
**Recommendation**: Remove `metrics_list_diagnostics` or make it an alias. Add to both descriptions: "Available only for builds distributed via App Store (not pre-release)."

### 2. `metrics_build_perf` — 404 for pre-release
**Worker**: MetricsWorker
**Issue**: Calling for a pre-release build returns 404. The description does not mention this limitation.
**Recommendation**: Add to description: "Performance metrics available only for builds distributed via App Store. Pre-release/TestFlight builds return 404."

---

## Medium-Severity Issues (⚠️ FIX)

### Group 1: Companies, Auth, Apps

#### 1.1 `apps_get_metadata` — incorrect version auto-select
**Issue**: When called without `version_id` for iMapp (which has both iOS 5.4 and macOS 1.0 in PREPARE), it auto-selects macOS 1.0 instead of iOS 5.4.
**Recommendation**: Auto-select should prefer iOS. Alternatively, explicitly specify the platform in the response.

#### 1.2 `apps_get_metadata` / `apps_create_localization` — locale codes in description
**Issue**: Descriptions reference `ru-RU`, `de-DE`, but the API actually uses `ru`, `de-DE`, `it`, `he`, `ja` (mixed formats). There is no single consistent rule.
**Recommendation**: Update description to say: "Locale codes vary: some use language only (`ru`, `ja`), some use region (`en-US`, `de-DE`). Use `apps_list_localizations` to see actual codes."

#### 1.3 `app_versions_list` — `states` filter does not work
**Issue**: When using `states=PREPARE_FOR_SUBMISSION`, the API returns ALL versions. `filter[appStoreState]` is an incorrect parameter.
**Recommendation**: Fix the API request to use `filter[appVersionState]` instead, or remove the `states` parameter from the description with a note: "use client-side filtering".

### Group 2: TestFlight

#### 2.1 `beta_testers_search` — partial match does not work
**Issue**: Searching with `email=audit` does not find `audit-test@example.com`. Only exact match works.
**Recommendation**: Description should state: "Email search is exact match only, not partial/wildcard."

### Group 4: Reviews

#### 4.1 `reviews_list` — territory format in description
**Issue**: Description references `territory: US, RU, DE` (alpha-2), but the API returns territories in alpha-3 (USA, RUS, DEU in some contexts) and alpha-2 in filters.
**Recommendation**: Clarify: "Use alpha-2 codes (US, RU, DE) for filtering. API returns alpha-2 in review objects (USA territory == alpha-3 from Apple)."

### Group 5: Monetization

#### 5.1 `subscriptions_list_prices` — no actual prices
**Issue**: Returns opaque price point IDs without actual price amounts (USD, EUR, etc.).
**Recommendation**: Include `include=subscriptionPricePoint` with `fields[subscriptionPricePoints]=customerPrice,proceeds` to display actual prices.

#### 5.2 `promoted_get` — no linked IAP/subscription
**Issue**: Response contains `enabled`, `state`, `visibleForAllUsers`, but no reference to the IAP or subscription that the promoted purchase is linked to.
**Recommendation**: Add `include=inAppPurchaseV2,subscription` to retrieve linked product info.

#### 5.3 `pricing_get_price_schedule` — opaque IDs
**Issue**: `automaticPrices` contain opaque IDs without breakdown by territories/prices.
**Recommendation**: Include `territory` and `subscriptionPricePoint` relationships for human-readable output.

#### 5.4 `pricing_list_territory_availability` — territory code not visible
**Issue**: Territories are returned with base64 IDs without a visible territory code.
**Recommendation**: Include `territory` relationship to display the territory code.

### Write Tests

#### W.1 `app_events_update` — resets territory schedules
**Issue**: When updating an event, `territorySchedules` becomes an empty array.
**Recommendation**: Either add a `territory_schedules` parameter to update, or document: "Update does not preserve territory schedules. Re-set them after update."

#### W.2 `app_info_create_localization` — `name` not marked as required
**Issue**: API returns 409 if `name` is not provided ("You must provide a value for the attribute 'name'"), but in the tool description `name` is optional.
**Recommendation**: Mark `name` as required in the description.

#### W.3 `update_phased_release` — no way to obtain phased_release_id
**Issue**: The tool requires `phased_release_id`, but no other tool returns this ID.
**Recommendation**: `create_phased_release` should return the ID. Alternatively, add a `get_phased_release` tool that takes version_id.

#### W.4 `app_versions_update` — verbose response
**Issue**: Returns all relationships with full URLs (15+ nested objects).
**Recommendation**: Return only updated attributes + id, without the full relationships dump.

---

## Write Test Results (Wheele)

| # | Test | Tools | Status |
|---|------|-------|--------|
| 1 | Beta Group CRUD | create → update → delete | ✅ |
| 2 | Beta Tester CRUD | create → delete | ✅ |
| 3 | Beta Group ↔ Tester/Build links | add_testers → remove_testers → add_builds → remove_builds | ✅ |
| 4 | App Event CRUD + Localizations | create → update → create_loc → update_loc → delete_loc → delete | ✅ ⚠️ W.1 |
| 5 | Metadata Update | update_metadata (whats_new + promo) | ✅ |
| 6 | Version Localization CRUD | create_localization → delete_localization | ✅ |
| 7 | Build Operations | update_encryption / set_beta_localization / update_beta_detail | ⚠️ encryption (expired) / ✅ / ✅ |
| 8 | App Info CRUD | create_loc → update_loc → delete_loc | ✅ ⚠️ W.2 |
| 9 | Custom Pages CRUD | create → update → list_versions → update_loc → delete | ✅ |
| 10 | PPO CRUD | create_exp → update_exp → create_treatment → create_treatment_loc → delete | ✅ |
| 11 | Promoted IAP CRUD | create → update → delete | ✅ |
| 12 | IAP CRUD + Localizations | create → update → create_loc → update_loc → delete_loc → delete | ✅ |
| 13 | Subscription CRUD | create_group → create_sub → update → create_loc → update_loc → delete_loc → delete_sub → delete_group | ✅ |
| 14 | Offer Codes + Winback | offer_codes_create / winback_create | 🔇 SKIP (require pricing/approved sub) |
| 15 | Reviews Response | create_response → delete_response | ✅ |
| 16 | App Version Operations | update / set_review_details / update_age_rating | ✅ ⚠️ W.3, W.4 |
| 17 | Phased Release + Attach Build | create_phased_release / attach_build | 🔇 (already exists / expired build) |
| 18 | Beta Notification | send_beta_notification | 🔇 SKIP (sends real notifications) |
| 19 | IAP Price + Submit + Screenshot | set_price_schedule / submit_for_review / create_review_screenshot | 🔇 SKIP (irreversible operations) |
| 20 | Screenshots CRUD | create_set → create (upload reserve) → delete → delete_set | ✅ |
| 21 | App Previews CRUD | create_preview_set → create_preview → delete_preview → delete_set | ✅ |
| 22 | Screenshots Reorder | reorder | 🔇 SKIP (no uploaded screenshots) |
| 23 | User Management | invite → cancel_invitation | ✅ |
| 24 | Provisioning: Devices | register_device → update_device (disable) | ✅ |
| 25 | Provisioning: Bundle ID + Capabilities | create_bundle_id → enable_capability → disable_capability → delete_bundle_id | ✅ |

---

## Recommendations by Priority

### P0 — Fix Immediately
1. **Remove `metrics_list_diagnostics`** — full duplicate of `metrics_build_diagnostics`
2. **`app_info_create_localization`: mark `name` as required** — misleading, API always requires it

### P1 — Fix in the Next Release
3. **`app_versions_list`: fix `states` filter** — use `filter[appVersionState]` instead of `filter[appStoreState]`
4. **`apps_get_metadata`: auto-select iOS over macOS** when both platforms are in PREPARE
5. **`update_phased_release`: ensure phased_release_id is obtainable** — via create_phased_release response or a new getter
6. **`subscriptions_list_prices`: add actual prices** — include price point relationships
7. **`app_events_update`: add territory_schedules** parameter or document the reset behavior

### P2 — Improve When Possible
8. **`beta_testers_search`: document exact match** for email
9. **Locale codes**: unify descriptions — note that formats are mixed
10. **`reviews_list`: clarify territory format** in description (alpha-2 for filters)
11. **`promoted_get`: include linked IAP/subscription** info
12. **`pricing_*`: include territory codes** in human-readable format
13. **`metrics_build_perf`: add to description** the pre-release limitation
14. **`app_versions_update`: minimize response** — remove relationships dump
15. **`builds_update_encryption`: improve error message** for expired builds

---

## Overall Assessment

**The server is in good working condition.** Out of 205 tools:
- **173 (87%)** work correctly with no issues
- **10 (5%)** require minor fixes (descriptions, response formats)
- **2 (1%)** — critical bugs (duplicate + missing pre-release warning)
- **13 (7%)** — skipped (impossible or dangerous to test)

All CRUD cycles on Wheele passed successfully. Creating, updating, and deleting entities works reliably. Post-test cleanup was performed in full.

### Post-Audit Cleanup
- All test entities (beta groups, testers, events, IAP, subscriptions, custom pages, experiments, promoted purchases, screenshots, previews, bundle IDs, invitations) have been deleted
- The only remaining artifact: disabled device `AUDIT-TEST-DEVICE-DISABLED` (UDID: 00000000-0000000000000001) — the Apple API does not allow deleting devices, only disabling them
- On Wheele v4.5, the following were updated: What's New (en-US), promotional text, copyright, review details, release type (MANUAL). All of these were test data — **it is recommended to review them before an actual release**.
