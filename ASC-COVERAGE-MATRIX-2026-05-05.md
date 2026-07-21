# App Store Connect API Coverage Matrix

Date: 2026-05-05

Source baseline:
- Apple App Store Connect API overview: https://developer.apple.com/documentation/appstoreconnectapi
- Apple API 4.0 release notes: https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-0-release-notes
- Apple Webhook notifications: https://developer.apple.com/documentation/appstoreconnectapi/webhook-notifications

Update 2026-05-07: automated OpenAPI coverage tooling is now available. See `ASC-OPENAPI-COVERAGE-GENERATED.md` for the generated Apple 4.4.1 path/operation matrix.
Update 2026-05-08: accessibility declaration management is covered by `accessibility_*` tools.
Update 2026-05-08: local webhook receiver helpers are available for signature verification, payload parsing, and event/delivery triage.
Update 2026-07-20: Apple 4.4.1 versioned commerce metadata, plan-type-aware subscription availability, adjusted equalizations, and generic review submissions are covered.
Update 2026-07-21: Build Upload parents, file reservations, resumable transfers, commit recovery, and processing reconciliation are covered by `build_uploads_*` tools.
Update 2026-07-21: 11 TestFlight recruitment and usage-metric tools cover 12 additional Apple operations, including app-device context in tester projections.

This matrix tracks current `asc-mcp` coverage against the official App Store Connect API documentation. It is intentionally product-oriented: it names what users can do today, what is missing, and which additions should come first.

## Executive Priority

P0 additions:
- App Clips, background assets, app tags, routing app coverages, and customer review summaries.

P1 additions:
- Hosted webhook receiver templates and reusable triage resources/prompts.
- Merchant IDs and Pass Type IDs under provisioning.
- Analytics/customer-review summarization and metric recommendation ergonomics.

## Area Matrix

| Area | Status | Priority | Current worker keys | Missing / next |
|---|---|---:|---|---|
| Essentials: auth, errors, paging, uploads, rate limits | Partial | P1 | `auth` | API key inventory/revocation helpers |
| App Store app metadata and release operations | Partial | P0 | `apps`, `accessibility`, `versions`, `app_info`, `pricing`, `app_events`, `screenshots`, `custom_pages`, `ppo`, `promoted`, `review_attachments`, `review_submissions`, `reviews`, `export_compliance` | App Clips; background assets; app tags; routing app coverages; customer review summary endpoint |
| TestFlight builds, testers, groups, and beta app review | Partial | P0 | `builds`, `build_uploads`, `build_processing`, `export_compliance`, `build_beta`, `beta_groups`, `beta_feedback`, `beta_testers`, `beta_app`, `pre_release`, `beta_license`, `metrics` | beta app clip invocation/localization APIs |
| Webhook notifications | Covered | P2 | `webhooks` | OpenAPI drift checks and hosted receiver examples |
| Webhook notification receiver resources | Partial | P1 | `webhooks` | hosted receiver server templates; prompt/resource templates for event triage |
| In-app purchases, subscriptions, and offers | Partial | P2 | `iap`, `subscriptions` | authoritative fully paginated subscription inventory |
| Provisioning and identifiers | Partial | P1 | `provisioning` | merchant IDs; pass type IDs |
| Users, access, and sandbox testers | Partial | P2 | `users`, `sandbox` | API key inventory helpers; API key revocation workflow |
| Reporting, analytics, metrics, and diagnostics | Partial | P1 | `analytics`, `metrics` | analytics segment discovery ergonomics; customer review summarization; perf power metric recommendations |
| Xcode Cloud workflows and builds | Partial | P1 | `xcode_cloud` | workflow create/update/delete; product delete; relationship-only linkage endpoints |
| Game Center | Missing | P2 | none | Game Center details; leaderboards; achievements; activities; challenges |
| Alternative distribution | Missing | P2 | none | alternative marketplace and web distribution workflows |

## Implementation Order

1. Add `--read-only` runtime guard so static and live validation can run safely in production-like MCP hosts.
2. Update `AppsWorker` for app-level `accessibilityUrl` if Apple keeps it as a separate app metadata field outside declaration resources.
3. Add reusable webhook receiver playbooks and optional hosted receiver templates around the new local helper tools.
4. Add merchant/pass identifiers, App Clips, background assets, Game Center, and alternative distribution as larger domain workers.

## Safety Notes

- Mutation tools must remain statically reviewable without live App Store Connect calls.
- All new write tools should carry MCP annotations with `readOnlyHint = false`; destructive operations should carry `destructiveHint = true`.
- Live validation should stay read-only unless a user explicitly provides a sandbox-like target and confirms the exact mutation.
- Region- or entitlement-sensitive domains, especially alternative distribution, should be opt-in and clearly documented.
