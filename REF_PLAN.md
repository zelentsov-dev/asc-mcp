ASC MCP — Final Audit Report

  Tested: Groups 1-5 (~65 read tools)

  ---
  Group 1: Basics

  CompaniesWorker (3 tools)

  ┌─────────────────┬────────┬────────────────────────────────────┐
  │       Tool      │ Status │             Result                 │
  ├─────────────────┼────────┼────────────────────────────────────┤
  │ company_list    │ ✅ OK  │ 4 companies, active flag            │
  ├─────────────────┼────────┼────────────────────────────────────┤
  │ company_switch  │ ✅ OK  │ Switching by ID works               │
  ├─────────────────┼────────┼────────────────────────────────────┤
  │ company_current │ ✅ OK  │ Current company + Key ID + Issuer   │
  └─────────────────┴────────┴────────────────────────────────────┘

  AuthWorker (4 tools)

  ┌─────────────────────┬────────┬─────────────────────────────────────────┐
  │         Tool        │ Status │                 Result                  │
  ├─────────────────────┼────────┼─────────────────────────────────────────┤
  │ auth_generate_token │ ✅ OK  │ JWT generation                          │
  ├─────────────────────┼────────┼─────────────────────────────────────────┤
  │ auth_validate_token │ ✅ OK  │ Validation (invalid token handled correctly) │
  ├─────────────────────┼────────┼─────────────────────────────────────────┤
  │ auth_refresh_token  │ ✅ OK  │ Refresh                                 │
  ├─────────────────────┼────────┼─────────────────────────────────────────┤
  │ auth_token_status   │ ✅ OK  │ Cache, expiry, isValid                  │
  └─────────────────────┴────────┴─────────────────────────────────────────┘

  AppsWorker (7 read tools)

  ┌──────────────────────────────────┬─────────┬─────────────────────────────────────────────────────────────────────┐
  │               Tool               │ Status  │                              Result                                │
  ├──────────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────┤
  │ apps_list                        │ ✅ OK   │ 10 apps, pagination                                                │
  ├──────────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────┤
  │ apps_list (name filter)          │ ✅ OK   │ 1 result                                                           │
  ├──────────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────┤
  │ apps_get_details                 │ ✅ OK   │ Bundle, SKU, subscription URLs                                     │
  ├──────────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────┤
  │ apps_search                      │ ✅ OK   │ Search by name/bundleId                                            │
  ├──────────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────┤
  │ apps_list_versions               │ ⚠️  FIX  │ 175 versions without pagination/limit                              │
  ├──────────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────┤
  │ apps_get_metadata (no locale)    │ ⚠️  FIX  │ 72KB response, 20 locales                                          │
  ├──────────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────┤
  │ apps_get_metadata (locale)       │ ✅ OK   │ Single locale, compact                                             │
  ├──────────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────┤
  │ apps_get_metadata (auto version) │ ❌ FAIL │ Picks 1.0 (macOS) instead of 5.4 (iOS) — no platform priority      │
  ├──────────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────────┤
  │ apps_list_localizations          │ ✅ OK   │ 20 locales with hasDescription/hasWhatsNew flags                   │
  └──────────────────────────────────┴─────────┴─────────────────────────────────────────────────────────────────────┘

  Issues:
  1. ❌ apps_get_metadata without version_id: picks macOS 1.0 instead of iOS 5.4 — no platform priority
  2. ⚠️  apps_list_versions: no limit/pagination — always returns 175 entries
  3. ⚠️  apps_get_metadata without locale: 72KB — needs summary mode
  4. ⚠️  Locale description: example ru-RU is incorrect, actual code is ru
  5. ⚠️  No promotionalText in metadata response

  ---
  Group 2: Builds and TestFlight

  BuildsWorker (4 tools)

  ┌─────────────────────────┬────────┬───────────────────────────────────────────────┐
  │           Tool          │ Status │                   Result                      │
  ├─────────────────────────┼────────┼───────────────────────────────────────────────┤
  │ builds_list             │ ✅ OK  │ limit, sort, pagination work                  │
  ├─────────────────────────┼────────┼───────────────────────────────────────────────┤
  │ builds_get              │ ✅ OK  │ Details + betaDetail + preReleaseVersion (5.4) │
  ├─────────────────────────┼────────┼───────────────────────────────────────────────┤
  │ builds_find_by_number   │ ✅ OK  │ Build 71 found                                │
  ├─────────────────────────┼────────┼───────────────────────────────────────────────┤
  │ builds_list_for_version │ ✅ OK  │ Build for v5.3                                │
  └─────────────────────────┴────────┴───────────────────────────────────────────────┘

  Issue: builds_list does not show pre-release version string (5.4) — only build number (71). Need to include preReleaseVersion.

  BuildProcessingWorker (3 read tools)

  ┌──────────────────────────────┬────────┬──────────────────────────────────┐
  │             Tool             │ Status │            Result                │
  ├──────────────────────────────┼────────┼──────────────────────────────────┤
  │ builds_get_processing_state  │ ✅ OK  │ VALID + stateDescription         │
  ├──────────────────────────────┼────────┼──────────────────────────────────┤
  │ builds_get_processing_status │ ✅ OK  │ timeSinceUpload — convenient     │
  ├──────────────────────────────┼────────┼──────────────────────────────────┤
  │ builds_check_readiness       │ ✅ OK  │ Readiness checklist — excellent  │
  └──────────────────────────────┴────────┴──────────────────────────────────┘

  BuildBetaDetailsWorker (4 read tools)

  ┌────────────────────────────────┬────────┬──────────────────────────────┐
  │              Tool              │ Status │           Result             │
  ├────────────────────────────────┼────────┼──────────────────────────────┤
  │ builds_get_beta_detail         │ ✅ OK  │ Internal/External state      │
  ├────────────────────────────────┼────────┼──────────────────────────────┤
  │ builds_list_beta_localizations │ ✅ OK  │ 1 locale, whatsNew=null      │
  ├────────────────────────────────┼────────┼──────────────────────────────┤
  │ builds_get_beta_groups         │ ✅ OK  │ 1 group Develotex            │
  ├────────────────────────────────┼────────┼──────────────────────────────┤
  │ builds_get_beta_testers        │ ✅ OK  │ 0 testers (correct)          │
  └────────────────────────────────┴────────┴──────────────────────────────┘

  BetaGroupsWorker (2 read tools)

  ┌──────────────────────────┬────────┬─────────────────────────┐
  │           Tool           │ Status │         Result          │
  ├──────────────────────────┼────────┼─────────────────────────┤
  │ beta_groups_list         │ ✅ OK  │ 1 internal group        │
  ├──────────────────────────┼────────┼─────────────────────────┤
  │ beta_groups_list_testers │ ✅ OK  │ 15 testers with state   │
  └──────────────────────────┴────────┴─────────────────────────┘

  BetaTestersWorker (4 read tools)

  ┌────────────────────────┬─────────┬───────────────────────────────────────────────────────────────┐
  │          Tool          │ Status  │                           Result                              │
  ├────────────────────────┼─────────┼───────────────────────────────────────────────────────────────┤
  │ beta_testers_list      │ ✅ OK   │ Pagination works                                              │
  ├────────────────────────┼─────────┼───────────────────────────────────────────────────────────────┤
  │ beta_testers_search    │ ❌ FAIL │ "vadim" → 0 results — requires exact email, not partial match │
  ├────────────────────────┼─────────┼───────────────────────────────────────────────────────────────┤
  │ beta_testers_get       │ ✅ OK   │ Include apps + betaGroups works                               │
  ├────────────────────────┼─────────┼───────────────────────────────────────────────────────────────┤
  │ beta_testers_list_apps │ ✅ OK   │ Tester's apps                                                 │
  └────────────────────────┴─────────┴───────────────────────────────────────────────────────────────┘

  Issues:
  1. ❌ beta_testers_search: partial match does not work, description is misleading
  2. ⚠️  beta_testers_list: state=null (state is only shown in group context)

  ---
  Group 3: App Store Lifecycle

  AppLifecycleWorker (2 read tools)

  ┌────────────────────────────┬─────────┬─────────────────────────────────────────────────────────────────┐
  │            Tool            │ Status  │                            Result                               │
  ├────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────┤
  │ app_versions_list          │ ⚠️  FIX  │ Works but has huge relationships blocks (links)                  │
  ├────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────┤
  │ app_versions_list (states) │ ❌ FAIL │ appStoreVersionState is not a valid parameter — needs appStoreState │
  ├────────────────────────────┼─────────┼─────────────────────────────────────────────────────────────────┤
  │ app_versions_get           │ ⚠️  FIX  │ Data present, but relationships bloat the response              │
  └────────────────────────────┴─────────┴─────────────────────────────────────────────────────────────────┘

  Issues:
  1. ❌ states filter is broken — uses filter[appStoreVersionState] instead of the correct one
  2. ⚠️  relationships in response — 80% noise (links to endpoints). Needs cleanup
  3. ⚠️  Overlap with apps_list_versions — unclear when to use which

  AppInfoWorker (3 read tools)

  ┌─────────────────────────────┬────────┬────────────────────────────────────────┐
  │             Tool            │ Status │               Result                   │
  ├─────────────────────────────┼────────┼────────────────────────────────────────┤
  │ app_info_list               │ ✅ OK  │ 2 appInfos with age rating             │
  ├─────────────────────────────┼────────┼────────────────────────────────────────┤
  │ app_info_get                │ ✅ OK  │ Categories + localizations (with include) │
  ├─────────────────────────────┼────────┼────────────────────────────────────────┤
  │ app_info_list_localizations │ ✅ OK  │ 20 locales with subtitle               │
  └─────────────────────────────┴────────┴────────────────────────────────────────┘

  ---
  Group 4: Reviews

  ReviewsWorker (5 read tools)

  ┌─────────────────────────────────┬────────┬───────────────────────────────────────────┐
  │               Tool              │ Status │                 Result                    │
  ├─────────────────────────────────┼────────┼───────────────────────────────────────────┤
  │ reviews_list                    │ ✅ OK  │ 5929 reviews, sorting, pagination         │
  ├─────────────────────────────────┼────────┼───────────────────────────────────────────┤
  │ reviews_list (rating=1)         │ ✅ OK  │ 1353 negative                             │
  ├─────────────────────────────────┼────────┼───────────────────────────────────────────┤
  │ reviews_list (territory=USA)    │ ✅ OK  │ 1510 from USA (alpha-3!)                  │
  ├─────────────────────────────────┼────────┼───────────────────────────────────────────┤
  │ reviews_list (include_response) │ ✅ OK  │ Works                                     │
  ├─────────────────────────────────┼────────┼───────────────────────────────────────────┤
  │ reviews_get                     │ ✅ OK  │ Full review                               │
  ├─────────────────────────────────┼────────┼───────────────────────────────────────────┤
  │ reviews_list_for_version        │ ✅ OK  │ 5 reviews for v5.3                        │
  ├─────────────────────────────────┼────────┼───────────────────────────────────────────┤
  │ reviews_stats                   │ ✅ OK  │ Rating distribution + top territories     │
  └─────────────────────────────────┴────────┴───────────────────────────────────────────┘

  Issues:
  1. ⚠️  territory description: e.g., US, RU, DE — API requires alpha-3: USA, RUS, DEU
  2. ⚠️  reviews_stats: default period=last_month yields little data (2 reviews). all_time is better

  ---
  Group 5: Monetization

  InAppPurchasesWorker (5 read tools)

  ┌────────────────────────────┬────────┬────────────────────────────────────────────────────────┐
  │            Tool            │ Status │                       Result                           │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────┤
  │ iap_list                   │ ✅ OK  │ 2 IAP (NON_RENEWING)                                   │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────┤
  │ iap_get                    │ ✅ OK  │ Purchase details                                       │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────┤
  │ iap_list_subscriptions     │ ✅ OK  │ 2 subscription groups                                  │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────┤
  │ iap_get_subscription_group │ ⚠️  FIX │ Does not include subscriptions even with include_subscriptions=true │
  ├────────────────────────────┼────────┼────────────────────────────────────────────────────────┤
  │ iap_list_localizations     │ ✅ OK  │ 6 locales                                              │
  └────────────────────────────┴────────┴────────────────────────────────────────────────────────┘

  SubscriptionsWorker (2 read tools)

  ┌────────────────────┬────────┬──────────────────────────┐
  │        Tool        │ Status │         Result           │
  ├────────────────────┼────────┼──────────────────────────┤
  │ subscriptions_list │ ✅ OK  │ 11 subscriptions in group │
  ├────────────────────┼────────┼──────────────────────────┤
  │ subscriptions_get  │ ✅ OK  │ Subscription details     │
  └────────────────────┴────────┴──────────────────────────┘

  OfferCodesWorker (1 read tool)

  ┌──────────────────┬────────┬───────────────────────────┐
  │       Tool       │ Status │         Result            │
  ├──────────────────┼────────┼───────────────────────────┤
  │ offer_codes_list │ ✅ OK  │ 0 offer codes (correct)   │
  └──────────────────┴────────┴───────────────────────────┘

  WinBackOffersWorker (1 read tool)

  ┌──────────────┬────────┬───────────────────┐
  │     Tool     │ Status │     Result        │
  ├──────────────┼────────┼───────────────────┤
  │ winback_list │ ✅ OK  │ 0 win-back offers │
  └──────────────┴────────┴───────────────────┘

  PromotedPurchasesWorker (1 read tool)

  ┌───────────────┬────────┬─────────────────────┐
  │      Tool     │ Status │      Result         │
  ├───────────────┼────────┼─────────────────────┤
  │ promoted_list │ ✅ OK  │ 1 promoted purchase │
  └───────────────┴────────┴─────────────────────┘

  PricingWorker (2 read tools)

  ┌──────────────────────────┬────────┬────────────────────────────────┐
  │           Tool           │ Status │           Result               │
  ├──────────────────────────┼────────┼────────────────────────────────┤
  │ pricing_list_territories │ ✅ OK  │ Pagination, currency           │
  ├──────────────────────────┼────────┼────────────────────────────────┤
  │ pricing_get_availability │ ✅ OK  │ availableInNewTerritories=true │
  └──────────────────────────┴────────┴────────────────────────────────┘

  ---
  NOT TESTED (Groups 6-9)

  ┌──────────────────────────────────────────┬───────┬──────────────────┐
  │                  Group                   │ Tools │     Status       │
  ├──────────────────────────────────────────┼───────┼──────────────────┤
  │ 6. Analytics + Metrics                   │ ~10   │ ⏳ Not started   │
  ├──────────────────────────────────────────┼───────┼──────────────────┤
  │ 7. Screenshots                           │ ~3    │ ⏳ Not started   │
  ├──────────────────────────────────────────┼───────┼──────────────────┤
  │ 8. Marketing (Events, Custom Pages, PPO) │ ~8    │ ⏳ Not started   │
  ├──────────────────────────────────────────┼───────┼──────────────────┤
  │ 9. Infrastructure (Provisioning, Users)  │ ~10   │ ⏳ Not started   │
  ├──────────────────────────────────────────┼───────┼──────────────────┤
  │ Write tests on Wheele                    │ ~111  │ ⏳ Not started   │
  └──────────────────────────────────────────┴───────┴──────────────────┘

  ---
  Bug Summary (by priority)

  ❌ CRITICAL (3)

  1. apps_get_metadata auto-version — picks macOS 1.0 instead of iOS 5.4. Need priority: iOS > macOS, latest createdDate
  2. app_versions_list states filter — appStoreVersionState is not a valid API parameter. Need appStoreState
  3. beta_testers_search — partial match by email does not work. Description is misleading

  ⚠️  FIX (8)

  4. apps_list_versions — no limit/pagination, always returns 175 entries
  5. apps_get_metadata without locale — 72KB response, needs summary mode
  6. territory codes in reviews_list/reviews_list_for_version descriptions — says US, RU, but API expects USA, RUS
  7. locale examples — description says ru-RU, actual code is ru
  8. iap_get_subscription_group — include_subscriptions does not work
  9. app_versions_list/get — relationships blocks bloat the response (80% noise)
  10. builds_list — does not show pre-release version string (5.4), only build number
  11. reviews_stats — default period=last_month yields little data

  Recommendations

  - Add limit parameter to apps_list_versions
  - Clean up relationships from app_versions_list/get (remove links)
  - Automatically convert alpha-2 → alpha-3 territory codes
  - Add platform filter to auto-version selection for metadata
  - beta_testers_search — implement partial match or rename to beta_testers_find_by_email
