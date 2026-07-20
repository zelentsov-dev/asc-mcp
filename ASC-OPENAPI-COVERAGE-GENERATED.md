# App Store Connect OpenAPI Coverage

Generated: 2026-07-20

Sources:
- Apple App Store Connect API overview: https://developer.apple.com/app-store-connect/api/
- Apple App Store Connect API documentation: https://developer.apple.com/documentation/appstoreconnectapi
- Apple OpenAPI specification download: https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip

Spec: App Store Connect API 4.4.1 (OpenAPI 3.0.1)
Apple paths: 966
Apple operations: 1263
Classified paths: 966
Unclassified paths: 0

## Priority Gaps

- P0 App Store app metadata and release operations: Partial, 303 Apple paths, 380 operations.
- P0 TestFlight builds, testers, groups, and beta app review: Partial, 115 Apple paths, 154 operations.
- P1 Provisioning and identifiers: Partial, 32 Apple paths, 49 operations.
- P1 Reporting, analytics, metrics, and diagnostics: Partial, 47 Apple paths, 56 operations.
- P1 Xcode Cloud workflows and builds: Partial, 56 Apple paths, 59 operations.

## Domain Matrix

| Domain | Status | Priority | Apple paths | Operations | Workers | Notes |
|---|---|---:|---:|---:|---|---|
| App Store app metadata and release operations | Partial | P0 | 303 | 380 | `apps`, `accessibility`, `versions`, `app_info`, `pricing`, `app_events`, `screenshots`, `custom_pages`, `ppo`, `promoted`, `review_attachments`, `reviews`, `export_compliance` | The common release workflow includes strict version filtering and paging, safe phased-release controls, and App Info-owned age-rating inspection. API 4.0 app-surface additions remain the highest App Store coverage gap. |
| TestFlight builds, testers, groups, and beta app review | Partial | P0 | 115 | 154 | `builds`, `build_processing`, `export_compliance`, `build_beta`, `beta_groups`, `beta_feedback`, `beta_testers`, `beta_app`, `pre_release`, `beta_license` | Core TestFlight administration and dedicated beta feedback retrieval are covered; recruitment criteria and beta App Clip APIs remain the main gaps. |
| Essentials: auth, errors, paging, uploads, rate limits | Partial | P1 | 0 | 0 | `auth` | Core runtime behavior is covered; OpenAPI drift is now generated from Apple's official specification. |
| Provisioning and identifiers | Partial | P1 | 32 | 49 | `provisioning` | Core signing automation exists; Wallet and Apple Pay identifiers are useful next additions. |
| Reporting, analytics, metrics, and diagnostics | Partial | P1 | 47 | 56 | `analytics`, `metrics` | Read-heavy workflows are safe and valuable; summaries and recommendations are high UX leverage. |
| Webhook notification receiver resources | Partial | P1 | 0 | 0 | `webhooks` | Local receiver helpers are now available and remain read-only; future work can add deployable receiver templates and reusable playbooks. |
| Xcode Cloud workflows and builds | Partial | P1 | 56 | 59 | `xcode_cloud` | Covers read-heavy CI dashboards plus start/rebuild build runs; destructive workflow/product management remains intentionally deferred. |
| Alternative distribution | Missing | P2 | 21 | 28 | none | Region- and entitlement-sensitive APIs should be opt-in and strongly documented. |
| Game Center | Missing | P2 | 238 | 337 | none | Large domain; should be added only after OpenAPI-driven scaffolding is in place. |
| In-app purchases, subscriptions, and offers | Partial | P2 | 172 | 218 | `iap`, `subscriptions` | v3 consolidates subscription offers under subscriptions_* and keeps one-time IAP product management under iap_*. Legacy subscriptionAvailability tools remain for compatibility; plan-type-aware availability and a complete inventory are pending. |
| Users, access, and sandbox testers | Partial | P2 | 13 | 20 | `users`, `sandbox` | User management is serviceable; API key operations should remain carefully annotated as high-risk. |
| Webhook notifications | Covered | P2 | 6 | 8 | `webhooks` | Covers app webhooks, individual webhook reads, create/update/delete, delivery listing, redelivery, ping testing, and local receiver diagnostics. |

## Missing Apple Domains

- Alternative distribution: 21 paths, 28 operations.
- Game Center: 238 paths, 337 operations.

## Unclassified Apple Paths

All Apple paths matched at least one maintained coverage rule.

## How To Regenerate

```bash
rm -rf /tmp/asc-openapi
mkdir -p /tmp/asc-openapi
curl -L --fail -o /tmp/asc-openapi/spec.zip https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip
unzip -q /tmp/asc-openapi/spec.zip -d /tmp/asc-openapi
swift run asc-mcp openapi-coverage --spec /tmp/asc-openapi/openapi.oas.json --output ASC-OPENAPI-COVERAGE-GENERATED.md
```
