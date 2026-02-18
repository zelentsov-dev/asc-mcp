# ASC MCP — Workers Audit

## Goal

Systematic review of **25 workers (205 tools)** in the ASC MCP server. For each worker:
1. Verify that read operations work correctly (list/get)
2. Evaluate response usability (structure, completeness, unnecessary data)
3. Verify tool descriptions (parameter accuracy, examples)
4. Identify bugs and inconsistencies
5. Assess the need for write operations (create/update/delete) — but **DO NOT** execute mutations

## Evaluation Criteria

Each worker is rated on the following scale:

| Rating | Meaning |
|--------|---------|
| ✅ OK | Works correctly, convenient response |
| ⚠️ FIX | Works, but needs fixes (description, format, usability) |
| ❌ FAIL | Does not work or has a critical bug |
| 🔇 SKIP | No data for testing / write-only / unsafe to test |

For each tool, the following is recorded:
- **Status**: ✅/⚠️/❌/🔇
- **Response**: brief description of what was returned
- **Issues**: bugs, inaccuracies in description, inconvenient format
- **Recommendation**: what to fix

## Test Data

| Company | ID | Application | App ID |
|---------|-----|------------|--------|
| Awared SLU | 4 | iMapp | 886626229 |
| FINDUS | 1 | Find Us | 1455353365 |

## Audit Order

### Group 1: Basics (partially verified already)

#### 1.1 CompaniesWorker (3 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `company_list` | Call without parameters | List of 4 companies with active flag |
| `company_switch` | Switch to ID=4 | Confirmation of switch |
| `company_current` | Call after switch | Current company = Awared SLU |

#### 1.2 AuthWorker (4 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `auth_generate_token` | Generate JWT | Valid token |
| `auth_validate_token` | Validate the generated token | valid: true + expiration |
| `auth_refresh_token` | Refresh token | New token |
| `auth_token_status` | Current token status | Lifetime, expiry |

#### 1.3 AppsWorker (9 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `apps_list` | Without filters | All Awared SLU apps |
| `apps_list` | name="iMapp" | 1 result |
| `apps_get_details` | app_id=886626229 | Bundle, SKU, subscription URLs |
| `apps_search` | Search for "Find" | Relevant results |
| `apps_list_versions` | app_id=886626229 | 175 versions, sorted |
| `apps_get_metadata` | app_id=886626229 (without locale) | ALL locales |
| `apps_get_metadata` | locale=ru-RU | Russian locale only |
| `apps_list_localizations` | app_id=886626229 | List of available locales |
| `apps_create_localization` | 🔇 SKIP — mutation |  |
| `apps_delete_localization` | 🔇 SKIP — mutation |  |
| `apps_update_metadata` | 🔇 SKIP — mutation |  |

**Verify**: whether description, whatsNew, keywords, promotionalText are present in metadata; version response format (avoid pulling all 175?)

---

### Group 2: Builds and TestFlight

#### 2.1 BuildsWorker (4 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `builds_list` | app_id=886626229, limit=5, sort=-uploadedDate | 5 most recent builds |
| `builds_get` | build_id from previous response | Details: version, state, min OS |
| `builds_find_by_number` | version="71" | Build 71 |
| `builds_list_for_version` | version_id from apps_list_versions | Builds for version 5.3 |

**Verify**: whether pre-release version string is present (5.4 vs build 71); how convenient it is to find a build by app version number.

#### 2.2 BuildProcessingWorker (4 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `builds_get_processing_state` | build_id of the latest | VALID/PROCESSING |
| `builds_get_processing_status` | build_id of the latest | Detailed status |
| `builds_check_readiness` | build_id of the latest | Release readiness |
| `builds_update_encryption` | 🔇 SKIP — mutation |  |

#### 2.3 BuildBetaDetailsWorker (8 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `builds_get_beta_detail` | build_id of the latest | Beta state, auto-notify |
| `builds_list_beta_localizations` | build_id of the latest | What to Test for each locale |
| `builds_get_beta_groups` | build_id of the latest | Tester groups for the build |
| `builds_get_beta_testers` | build_id of the latest | Testers with access |
| `builds_update_beta_detail` | 🔇 SKIP — mutation |  |
| `builds_set_beta_localization` | 🔇 SKIP — mutation |  |
| `builds_add_to_beta_groups` | 🔇 SKIP — mutation |  |
| `builds_send_beta_notification` | 🔇 SKIP — mutation |  |

#### 2.4 BetaGroupsWorker (9 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `beta_groups_list` | app_id=886626229 | List of groups (Internal, External) |
| `beta_groups_list_testers` | group_id from the list | Testers in the group |
| `beta_groups_create` | 🔇 SKIP — mutation |  |
| `beta_groups_update` | 🔇 SKIP — mutation |  |
| `beta_groups_delete` | 🔇 SKIP — mutation |  |
| `beta_groups_add_testers` | 🔇 SKIP — mutation |  |
| `beta_groups_remove_testers` | 🔇 SKIP — mutation |  |
| `beta_groups_add_builds` | 🔇 SKIP — mutation |  |
| `beta_groups_remove_builds` | 🔇 SKIP — mutation |  |

#### 2.5 BetaTestersWorker (6 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `beta_testers_list` | limit=10 | List of testers with email/name |
| `beta_testers_search` | email fragment | Find a specific tester |
| `beta_testers_get` | tester_id from the list | Full tester data |
| `beta_testers_list_apps` | tester_id | Tester's apps |
| `beta_testers_create` | 🔇 SKIP — mutation |  |
| `beta_testers_delete` | 🔇 SKIP — mutation |  |

---

### Group 3: App Store Lifecycle

#### 3.1 AppLifecycleWorker (12 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `app_versions_list` | app_id=886626229 | Versions with states |
| `app_versions_get` | version_id READY_FOR_SALE (5.3) | Version details |
| `app_versions_get` | version_id PREPARE_FOR_SUBMISSION (5.4) | Details + editableFields |
| `app_versions_create` | 🔇 SKIP — mutation |  |
| `app_versions_update` | 🔇 SKIP — mutation |  |
| `app_versions_attach_build` | 🔇 SKIP — mutation |  |
| `app_versions_submit_for_review` | 🔇 SKIP — mutation |  |
| `app_versions_cancel_review` | 🔇 SKIP — mutation |  |
| `app_versions_create_phased_release` | 🔇 SKIP — mutation |  |
| `app_versions_update_phased_release` | 🔇 SKIP — mutation |  |
| `app_versions_release` | 🔇 SKIP — mutation |  |
| `app_versions_set_review_details` | 🔇 SKIP — mutation |  |
| `app_versions_update_age_rating` | 🔇 SKIP — mutation |  |

**Verify**: overlap with apps_list_versions; difference between app_versions_list vs apps_list_versions.

#### 3.2 AppInfoWorker (7 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `app_info_list` | app_id=886626229 | List of appInfos (categories, age rating) |
| `app_info_get` | app_info_id from the list | Category, age rating |
| `app_info_list_localizations` | app_info_id | Category localizations |
| `app_info_update` | 🔇 SKIP — mutation |  |
| `app_info_update_localization` | 🔇 SKIP — mutation |  |
| `app_info_create_localization` | 🔇 SKIP — mutation |  |
| `app_info_delete_localization` | 🔇 SKIP — mutation |  |

**Verify**: overlap with apps_get_metadata — are both needed?

---

### Group 4: Reviews

#### 4.1 ReviewsWorker (7 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `reviews_list` | app_id, limit=5, sort=-createdDate | Last 5 reviews |
| `reviews_list` | rating=1 | Negative reviews only |
| `reviews_list` | territory=USA | US only (alpha-3!) |
| `reviews_list` | rating=5, territory=RUS | Combo filter |
| `reviews_list` | include_response=true | With developer responses |
| `reviews_get` | review_id from the list | Full review |
| `reviews_list_for_version` | version_id=e7907be8... (v5.3) | Reviews for a specific version |
| `reviews_stats` | app_id=886626229 | Rating statistics |
| `reviews_create_response` | 🔇 SKIP — mutation |  |
| `reviews_delete_response` | 🔇 SKIP — mutation |  |
| `reviews_get_response` | review_id with has_response=true | Developer response |

**Known bug**: territory description says `e.g., US, RU, DE` — API expects alpha-3 (`USA, RUS, DEU`).

---

### Group 5: Monetization

#### 5.1 InAppPurchasesWorker (17 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `iap_list` | app_id=886626229 | List of IAPs (consumable, non-consumable) |
| `iap_get` | iap_id from the list | Purchase details |
| `iap_list_subscriptions` | app_id=886626229 | Subscription groups |
| `iap_get_subscription_group` | group_id=20410719 | Extended version group details |
| `iap_list_localizations` | iap_id | Name localizations |
| `iap_list_price_points` | iap_id | Price points by country |
| `iap_get_price_schedule` | iap_id | Current prices |
| `iap_get_review_screenshot` | iap_id | Review screenshot |
| `iap_create` | 🔇 SKIP — mutation |  |
| `iap_update` | 🔇 SKIP — mutation |  |
| `iap_delete` | 🔇 SKIP — mutation |  |
| `iap_create_localization` | 🔇 SKIP — mutation |  |
| `iap_update_localization` | 🔇 SKIP — mutation |  |
| `iap_delete_localization` | 🔇 SKIP — mutation |  |
| `iap_submit_for_review` | 🔇 SKIP — mutation |  |
| `iap_set_price_schedule` | 🔇 SKIP — mutation |  |
| `iap_create_review_screenshot` | 🔇 SKIP — mutation |  |

#### 5.2 SubscriptionsWorker (15 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `subscriptions_list` | group_id=20410719 | Subscriptions in the group |
| `subscriptions_get` | subscription_id from the list | Subscription details |
| `subscriptions_list_localizations` | subscription_id | Localizations |
| `subscriptions_list_prices` | subscription_id | Current prices |
| `subscriptions_list_price_points` | subscription_id | All available price points |
| `subscriptions_create` | 🔇 SKIP — mutation |  |
| `subscriptions_update` | 🔇 SKIP — mutation |  |
| `subscriptions_delete` | 🔇 SKIP — mutation |  |
| `subscriptions_create_localization` | 🔇 SKIP — mutation |  |
| `subscriptions_update_localization` | 🔇 SKIP — mutation |  |
| `subscriptions_delete_localization` | 🔇 SKIP — mutation |  |
| `subscriptions_create_group` | 🔇 SKIP — mutation |  |
| `subscriptions_update_group` | 🔇 SKIP — mutation |  |
| `subscriptions_delete_group` | 🔇 SKIP — mutation |  |
| `subscriptions_submit` | 🔇 SKIP — mutation |  |

**Verify**: overlap with iap_list_subscriptions — are both needed?

#### 5.3 OfferCodesWorker (7 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `offer_codes_list` | subscription_id | List of offer codes |
| `offer_codes_list_prices` | offer_code_id | Offer prices |
| `offer_codes_list_one_time` | offer_code_id | One-time use codes |
| `offer_codes_create` | 🔇 SKIP — mutation |  |
| `offer_codes_update` | 🔇 SKIP — mutation |  |
| `offer_codes_deactivate` | 🔇 SKIP — mutation |  |
| `offer_codes_generate_one_time` | 🔇 SKIP — mutation |  |

#### 5.4 WinBackOffersWorker (5 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `winback_list` | subscription_id | Win-back offers |
| `winback_list_prices` | winback_id | Prices |
| `winback_create` | 🔇 SKIP — mutation |  |
| `winback_update` | 🔇 SKIP — mutation |  |
| `winback_delete` | 🔇 SKIP — mutation |  |

#### 5.5 PromotedPurchasesWorker (5 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `promoted_list` | app_id=886626229 | Promoted IAPs |
| `promoted_get` | promoted_id | Details |
| `promoted_create` | 🔇 SKIP — mutation |  |
| `promoted_update` | 🔇 SKIP — mutation |  |
| `promoted_delete` | 🔇 SKIP — mutation |  |

#### 5.6 PricingWorker (6 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `pricing_list_territories` | Without parameters | ~175 territories |
| `pricing_get_availability` | app_id=886626229 | Availability by country |
| `pricing_list_price_points` | app_id | Price points |
| `pricing_get_price_schedule` | app_id | Price schedule |
| `pricing_list_territory_availability` | app_id | Availability by territory |
| `pricing_set_price_schedule` | 🔇 SKIP — mutation |  |

---

### Group 6: Analytics and Metrics (partially verified)

#### 6.1 AnalyticsWorker (11 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `analytics_app_summary` | date=2026-02-14, app_id=886626229 | ✅ Already verified — 4 sections |
| `analytics_sales_report` | SALES/SUMMARY/DAILY | ✅ Already verified |
| `analytics_sales_report` | SUBSCRIPTION/SUMMARY/DAILY | ✅ Already verified |
| `analytics_sales_report` | SUBSCRIPTION_EVENT/SUMMARY/DAILY | ✅ Already verified |
| `analytics_sales_report` | SUBSCRIBER/DETAILED/DAILY | ✅ Already verified |
| `analytics_sales_report` | summary_only=false, limit=5 | ✅ Already verified |
| `analytics_financial_report` | region_code=US, date=2026-01 | Financial report |
| `analytics_financial_report` | summary_only=true vs false | Compare formats |
| `analytics_list_report_requests` | app_id=886626229 | ONGOING requests |
| `analytics_create_report_request` | 🔇 SKIP — already created |  |
| `analytics_check_snapshot_status` | request_id=5a1abc6b... | ✅ Already verified — 0/142 |
| `analytics_list_reports` | request_id=5a1abc6b... | List of reports |
| `analytics_list_instances` | report_id from list_reports | Instances |
| `analytics_get_instance` | instance_id | Details |
| `analytics_list_segments` | instance_id | Segments with download URL |

**Known issues**:
- vendor_number for Awared SLU — SALES DETAILED returns "Invalid vendor number"
- Report snapshot 142 — all pending

#### 6.2 MetricsWorker (5 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `metrics_app_perf` | app_id=886626229 | Performance metrics (launch time, hangs) |
| `metrics_build_perf` | build_id of the latest | Metrics for a specific build |
| `metrics_list_diagnostics` | app_id=886626229 | Diagnostic data |
| `metrics_build_diagnostics` | build_id | Build diagnostics |
| `metrics_get_diagnostic_logs` | diagnostic_id | Logs |

---

### Group 7: Screenshots and Media

#### 7.1 ScreenshotsWorker (12 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `screenshots_list_sets` | version_id (READY_FOR_SALE) | Screenshot sets by display type |
| `screenshots_list` | set_id from the list | Screenshots in the set |
| `screenshots_list_preview_sets` | version_id | App Preview sets |
| `screenshots_create_set` | 🔇 SKIP — mutation |  |
| `screenshots_delete_set` | 🔇 SKIP — mutation |  |
| `screenshots_create` | 🔇 SKIP — mutation |  |
| `screenshots_delete` | 🔇 SKIP — mutation |  |
| `screenshots_reorder` | 🔇 SKIP — mutation |  |
| `screenshots_create_preview_set` | 🔇 SKIP — mutation |  |
| `screenshots_delete_preview_set` | 🔇 SKIP — mutation |  |
| `screenshots_create_preview` | 🔇 SKIP — mutation |  |
| `screenshots_delete_preview` | 🔇 SKIP — mutation |  |

---

### Group 8: Marketing

#### 8.1 AppEventsWorker (9 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `app_events_list` | app_id=886626229 | In-app events |
| `app_events_get` | event_id | Event details |
| `app_events_list_localizations` | event_id | Localizations |
| `app_events_create` | 🔇 SKIP — mutation |  |
| `app_events_update` | 🔇 SKIP — mutation |  |
| `app_events_delete` | 🔇 SKIP — mutation |  |
| `app_events_create_localization` | 🔇 SKIP — mutation |  |
| `app_events_update_localization` | 🔇 SKIP — mutation |  |
| `app_events_delete_localization` | 🔇 SKIP — mutation |  |

#### 8.2 CustomProductPagesWorker (10 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `custom_pages_list` | app_id=886626229 | Custom product pages |
| `custom_pages_get` | page_id | Details |
| `custom_pages_list_versions` | page_id | Page versions |
| `custom_pages_list_localizations` | version_id | Localizations |
| `custom_pages_create` | 🔇 SKIP — mutation |  |
| `custom_pages_update` | 🔇 SKIP — mutation |  |
| `custom_pages_delete` | 🔇 SKIP — mutation |  |
| `custom_pages_create_version` | 🔇 SKIP — mutation |  |
| `custom_pages_create_localization` | 🔇 SKIP — mutation |  |
| `custom_pages_update_localization` | 🔇 SKIP — mutation |  |

#### 8.3 ProductPageOptimizationWorker (8 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `ppo_list_experiments` | app_id=886626229 | A/B tests |
| `ppo_get_experiment` | experiment_id | Experiment details |
| `ppo_list_treatments` | experiment_id | Variants |
| `ppo_list_treatment_localizations` | treatment_id | Variant localizations |
| `ppo_create_experiment` | 🔇 SKIP — mutation |  |
| `ppo_update_experiment` | 🔇 SKIP — mutation |  |
| `ppo_delete_experiment` | 🔇 SKIP — mutation |  |
| `ppo_create_treatment` | 🔇 SKIP — mutation |  |
| `ppo_create_treatment_localization` | 🔇 SKIP — mutation |  |

---

### Group 9: Infrastructure

#### 9.1 ProvisioningWorker (17 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `provisioning_list_bundle_ids` | Without filters | All bundle IDs |
| `provisioning_get_bundle_id` | bundle_id_resource_id | Details |
| `provisioning_list_devices` | Without filters | Registered devices |
| `provisioning_list_certificates` | Without filters | Certificates |
| `provisioning_get_certificate` | cert_id | Certificate details |
| `provisioning_list_profiles` | Without filters | Provisioning profiles |
| `provisioning_get_profile` | profile_id | Profile details |
| `provisioning_list_capabilities` | bundle_id_resource_id | Capabilities |
| `provisioning_create_bundle_id` | 🔇 SKIP — mutation |  |
| `provisioning_delete_bundle_id` | 🔇 SKIP — mutation |  |
| `provisioning_register_device` | 🔇 SKIP — mutation |  |
| `provisioning_update_device` | 🔇 SKIP — mutation |  |
| `provisioning_revoke_certificate` | 🔇 SKIP — mutation |  |
| `provisioning_delete_profile` | 🔇 SKIP — mutation |  |
| `provisioning_create_profile` | 🔇 SKIP — mutation |  |
| `provisioning_enable_capability` | 🔇 SKIP — mutation |  |
| `provisioning_disable_capability` | 🔇 SKIP — mutation |  |

#### 9.2 UsersWorker (7 tools)
| Tool | Test | Expected Result |
|------|------|-----------------|
| `users_list` | Without filters | All team members |
| `users_get` | user_id from the list | Role, email, access |
| `users_list_invitations` | Without filters | Pending invitations |
| `users_update` | 🔇 SKIP — mutation |  |
| `users_remove` | 🔇 SKIP — mutation |  |
| `users_invite` | 🔇 SKIP — mutation |  |
| `users_cancel_invitation` | 🔇 SKIP — mutation |  |

---

## Additional Checks (cross-worker)

### Pagination
- Verify `next_url` on 3+ workers — call the second page
- Ensure `limit` works correctly

### Tool Descriptions
- For each tool verify: description matches actual behavior
- Parameters: names, types, required/optional, example values
- Bugs like territory alpha-2 vs alpha-3

### Response Format
- Consistency: `success`, `count`, `next_url` across all list tools
- Unnecessary data: are we pulling 100KB JSON when only 1 line is needed
- Missing data: is all useful information included

### Cross-company
- Test 2-3 workers on FINDUS (company 1) — ensure company_switch works globally

---

## Final Report Format

```
## Worker: ReviewsWorker (7 tools)

### Tests
| Tool | Status | Result |
|------|--------|--------|
| reviews_list | ✅ | 5929 reviews, filters work |
| reviews_list (territory) | ⚠️ FIX | Alpha-2 codes do not work, alpha-3 required |
| reviews_stats | ❌ FAIL | 404 error |

### Issues
1. ⚠️ territory parameter: description says US/RU, API expects USA/RUS
2. ❌ reviews_stats: endpoint not implemented

### Recommendations
1. Add alpha-2 to alpha-3 conversion in the worker
2. Implement reviews_stats or remove from description
3. Add reviews_create_response to the description — use case for responding to negative reviews
```

---

## Effort Estimate

| Group | Tools to Test | Time Estimate |
|-------|---------------|---------------|
| 1. Basics | ~16 read | 15 min |
| 2. Builds + TestFlight | ~15 read | 15 min |
| 3. App Store Lifecycle | ~6 read | 10 min |
| 4. Reviews | ~8 read | 10 min |
| 5. Monetization | ~18 read | 20 min |
| 6. Analytics + Metrics | ~10 read | 15 min |
| 7. Screenshots | ~3 read | 5 min |
| 8. Marketing | ~8 read | 10 min |
| 9. Infrastructure | ~10 read | 10 min |
| **Total** | **~94 read tools** | **~2 hours** |

Write operations (~111 tools) are checked for description correctness only, without execution.
