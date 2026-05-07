# App Store Connect API Coverage Matrix

Date: 2026-05-05

Source baseline:
- Apple App Store Connect API overview: https://developer.apple.com/documentation/appstoreconnectapi
- Apple API 4.0 release notes: https://developer.apple.com/documentation/appstoreconnectapi/app-store-connect-api-4-0-release-notes
- Apple Webhook notifications: https://developer.apple.com/documentation/appstoreconnectapi/webhook-notifications

This matrix tracks current `asc-mcp` coverage against the official App Store Connect API documentation. It is intentionally product-oriented: it names what users can do today, what is missing, and which additions should come first.

## Executive Priority

P0 additions:
- Accessibility declarations, App Clips, background assets, app tags, routing app coverages, and customer review summaries.

P1 additions:
- Automated OpenAPI spec diff against `app-store-connect-openapi-specification.zip`.
- Webhook receiver-side signature verification, event payload decoder, and triage resources/prompts.
- Merchant IDs and Pass Type IDs under provisioning.
- Analytics/customer-review summarization and metric recommendation ergonomics.

## Area Matrix

| Area | Status | Priority | Current worker keys | Missing / next |
|---|---|---:|---|---|
| Essentials: auth, errors, paging, uploads, rate limits | Partial | P1 | `auth` | OpenAPI spec diff; API key inventory/revocation helpers |
| App Store app metadata and release operations | Partial | P0 | `apps`, `versions`, `app_info`, `pricing`, `app_events`, `screenshots`, `custom_pages`, `ppo`, `promoted`, `review_attachments`, `reviews` | accessibility declarations; App Clips; background assets; app tags; routing app coverages; customer review summary endpoint |
| TestFlight builds, testers, groups, and beta app review | Partial | P0 | `builds`, `build_processing`, `build_beta`, `beta_groups`, `beta_feedback`, `beta_testers`, `beta_app`, `pre_release`, `beta_license` | beta recruitment criteria; beta app clip invocation/localization APIs |
| Webhook notifications | Covered | P2 | `webhooks` | OpenAPI drift checks and receiver-side helper ergonomics |
| Webhook notification receiver resources | Missing | P1 | none | signature verification helpers; event payload decoder; prompt/resource templates for event triage |
| In-app purchases, subscriptions, and offers | Covered | P2 | `iap`, `subscriptions`, `offer_codes`, `winback`, `intro_offers`, `promo_offers` | OpenAPI drift checks and schema tightening |
| Provisioning and identifiers | Partial | P1 | `provisioning` | merchant IDs; pass type IDs |
| Users, access, and sandbox testers | Partial | P2 | `users`, `sandbox` | API key inventory helpers; API key revocation workflow |
| Reporting, analytics, metrics, and diagnostics | Partial | P1 | `analytics`, `metrics` | analytics segment discovery ergonomics; customer review summarization; perf power metric recommendations |
| Xcode Cloud workflows and builds | Partial | P1 | `xcode_cloud` | workflow create/update/delete; product delete; relationship-only linkage endpoints |
| Game Center | Missing | P2 | none | Game Center details; leaderboards; achievements; activities; challenges |
| Alternative distribution | Missing | P2 | none | alternative marketplace and web distribution workflows |

## Implementation Order

1. Add `--read-only` runtime guard so static and live validation can run safely in production-like MCP hosts.
2. Add `AccessibilityWorker` and update `AppsWorker` for `accessibilityUrl`: this closes a new compliance-oriented App Store gap.
3. Add OpenAPI drift tooling so future Apple release-note changes become visible before users report missing methods.
4. Add webhook receiver helpers: signature verification, event payload decoder, and triage prompts/resources.
5. Add merchant/pass identifiers, App Clips, background assets, Game Center, and alternative distribution as larger domain workers.

## Safety Notes

- Mutation tools must remain statically reviewable without live App Store Connect calls.
- All new write tools should carry MCP annotations with `readOnlyHint = false`; destructive operations should carry `destructiveHint = true`.
- Live validation should stay read-only unless a user explicitly provides a sandbox-like target and confirms the exact mutation.
- Region- or entitlement-sensitive domains, especially alternative distribution, should be opt-in and clearly documented.
