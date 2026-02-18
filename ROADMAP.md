# App Store Connect MCP Server - Roadmap

## Architecture and Priorities

### 🔴 Critical Features

#### 1. Release Pipeline (AppLifecycleWorker)
- **AppStoreVersions**: version creation, build attachment, submit for review
- **Release Management**: manual/auto/scheduled release, phased rollout
- **Builds**: search by number, processing status, encryption declarations
- **Media Upload**: screenshots, previews via uploadOperations

#### 2. TestFlight (TestFlightWorker)
- **Beta Groups & Testers**: group and tester management
- **Build Distribution**: attaching builds to groups
- **Beta App Review**: submitting for external testing
- **Test Info & Localizations**: information for testers

#### 3. Provisioning for CI/CD (ProvisioningWorker)
- **Devices**: UDID registration, batch operations
- **Certificates**: creation, revocation
- **Profiles**: creation, regeneration
- **Bundle IDs & Capabilities**: identifier management

### 🟡 Important Features

#### 4. Pricing & Availability (PricingWorker)
- **App Pricing**: prices and price points
- **Price Schedules**: scheduling changes
- **Territory Availability**: availability by country

#### 5. In-App Purchases & Subscriptions (IAPWorker)
- **IAP Management**: CRUD operations
- **Subscription Groups**: subscription management
- **Offers & Promos**: promo codes and offers
- **Localization & Media**: localizations and media

#### 6. Customer Reviews (ReviewsWorker)
- **Review Fetching**: retrieving reviews
- **Response Management**: responding to reviews
- **Auto-response Rules**: automatic responses
- **Analytics**: analysis and triage

#### 7. Users & Access (UsersAccessWorker)
- **User Management**: managing users
- **Invitations**: invitations
- **Roles & Permissions**: roles and permissions

#### 8. Reporting (ReportingWorker)
- **Sales & Trends**: sales reports
- **Finance Reports**: financial reports
- **Metrics & Analytics**: metrics and analytics

### 🟢 Nice-to-Have Features

#### 9. Xcode Cloud (XcodeCloudWorker)
- **Workflows**: CI/CD management
- **Build Runs**: launching and monitoring
- **Artifacts**: build artifacts

#### 10. Game Center (GameCenterWorker)
- **Achievements**: achievements
- **Leaderboards**: leaderboards
- **Localizations**: localizations

## Worker Breakdown

📋 **[Detailed method and API endpoint mapping](./WORKERS_API_MAPPING.md)**

### Existing (require refactoring)
```
AuthWorker (stays as is + improvements)
├── JWT caching (TTL ~20 min)
├── Auto-refresh on 401
└── Clock skew handling

AppsWorker → split into:
├── AppCatalogWorker (listing, search)
├── AppMetadataWorker (localizations, media)
└── AppLifecycleWorker (versions, releases)
```

### New Workers (by priority)
```
Phase 1: Critical
├── AppLifecycleWorker
├── BuildWorker
├── TestFlightWorker
└── MediaUploadWorker

Phase 2: CI/CD and Reviews
├── ProvisioningWorker
└── ReviewsWorker

Phase 3: Monetization
├── PricingWorker
└── IAPWorker

Phase 4: Analytics
├── ReportingWorker
└── WebhooksWorker

Phase 5: Additional
├── UsersAccessWorker
├── XcodeCloudWorker
├── GameCenterWorker
└── AlternativeDistributionWorker
```

### Shared Services (Services/)
```
Core Services
├── ASCClient (actor): HTTP client with JSON:API
├── RateLimiter: per-account rate limiting
├── Paginator: async stream pagination
├── ResourceCache: ETag/If-None-Match
├── MediaUploader: S3-like upload operations
├── ErrorMapper: unified error taxonomy
└── AuditLogger: logging and tracing
```

## Implementation Plan (Roadmap)

### Phase 0: Platform (1-2 weeks)
- [ ] Refactor ASCClient for JSON:API
- [ ] Implement RateLimiter with token bucket
- [ ] Paginator with AsyncThrowingStream
- [ ] ResourceCache with ETag support
- [ ] ErrorMapper for consistent errors
- [ ] Improve AuthWorker (JWT caching)

### Phase 1: Release Pipeline ✅ FULLY COMPLETED
- [x] **BuildsWorker** ✅
  - [x] Build search (`builds_list`, `builds_find_by_number`)
  - [x] Processing statuses (`builds_get_processing_state`, `builds_wait_for_processing`)
  - [x] Encryption declarations (`builds_update_encryption`)
  - [x] Build readiness checking (`builds_check_readiness`)
- [x] **BuildBetaDetailsWorker** (TestFlight) ✅
  - [x] Beta groups (`builds_get_beta_groups`)
  - [x] Beta testers (`builds_get_beta_testers`)
  - [x] Beta localizations (`builds_set_beta_localization`, `builds_list_beta_localizations`)
  - [x] Beta notifications (`builds_send_beta_notification`)
- [x] **BuildProcessingWorker** ✅
  - [x] Processing state management
  - [x] Expiration control (`builds_set_expiration`)
  - [x] Build readiness validation
- [x] **Technical Improvements** ✅
  - [x] SafeJSONHelpers - replacing unsafe `as Any`
  - [x] Structured JSON responses for all methods
  - [x] Enhanced error handling to prevent MCP disconnections
  - [x] Type-safe optional handling

- [x] **AppLifecycleWorker** ✅ COMPLETED
  - [x] Version creation (`app_versions_create`)
  - [x] Version management (`app_versions_list`, `app_versions_get`, `app_versions_update`)
  - [x] Build attachment (`app_versions_attach_build`)
  - [x] Submit for review (`app_versions_submit_for_review`, `app_versions_cancel_review`)
  - [x] Release management (`app_versions_release`)
  - [x] Phased rollout (`app_versions_create_phased_release`, `app_versions_update_phased_release`)
  - [x] Review details (`app_versions_set_review_details`) - with automatic POST/PATCH detection
  - [x] Age rating (`app_versions_update_age_rating`) - with automatic POST/PATCH detection

### Phase 2: CI/CD and Reviews ✅ COMPLETED
- [x] **ProvisioningWorker** ✅
  - [x] Bundle IDs CRUD (`provisioning_list_bundle_ids`, `provisioning_get_bundle_id`, `provisioning_create_bundle_id`, `provisioning_delete_bundle_id`)
  - [x] Devices management (`provisioning_list_devices`, `provisioning_register_device`, `provisioning_update_device`)
  - [x] Certificates listing (`provisioning_list_certificates`)
  - [x] Profiles listing (`provisioning_list_profiles`)
- [x] **ReviewsWorker** ✅ (implemented earlier)
  - [x] Reviews listing, stats, filtering
  - [x] Response management
- [x] **BetaGroupsWorker** ✅
  - [x] Beta groups CRUD (`beta_groups_list`, `beta_groups_create`, `beta_groups_update`, `beta_groups_delete`)
  - [x] Testers management (`beta_groups_add_testers`, `beta_groups_remove_testers`)

### Phase 3: Monetization ✅ COMPLETED
- [x] **InAppPurchasesWorker** ✅
  - [x] IAP CRUD (`iap_list`, `iap_get`, `iap_create`, `iap_update`, `iap_delete`)
  - [x] IAP Localizations (`iap_list_localizations`)
  - [x] Subscription groups (`iap_list_subscriptions`, `iap_get_subscription_group`)
- [ ] PricingWorker
  - [ ] Price points
  - [ ] Price schedules
  - [ ] Territory availability

### Phase 4: Analytics and Events (1-2 weeks)
- [ ] ReportingWorker
  - [ ] Sales reports
  - [ ] Finance reports
  - [ ] Metrics fetching
- [ ] WebhooksWorker
  - [ ] Event subscriptions
  - [ ] Delivery management
  - [ ] Retry logic

### Phase 5: Additional Features (on demand)
- [ ] UsersAccessWorker
- [ ] XcodeCloudWorker
- [ ] GameCenterWorker
- [ ] AlternativeDistributionWorker

## Practical Automation Scenarios

### Priority 1: One-click release
```swift
// Find build → create version → attach → submit → release
let build = await buildWorker.findBuild(number: "1.2.3")
let version = await lifecycleWorker.createVersion(app: appId, version: "1.2.0")
await lifecycleWorker.attachBuild(version: version, build: build)
await lifecycleWorker.submitForReview(version: version)
await lifecycleWorker.release(version: version, type: .automatic)
```

### Priority 2: TestFlight automation
```swift
// Create group → add testers → assign build
let group = await testFlightWorker.createGroup(name: "External Beta")
await testFlightWorker.addTesters(group: group, emails: csvEmails)
await testFlightWorker.assignBuild(group: group, build: latestBuild)
```

### Priority 3: Provisioning as code
```swift
// Sync from config
let config = ProvisioningConfig.load("provisioning.yml")
await provisioningWorker.sync(config: config)
// Auto-regenerate expired
await provisioningWorker.regenerateExpired()
```

### Priority 4: Review management
```swift
// Auto-respond based on rules
let rules = ReviewRules.load("review-rules.yml")
await reviewsWorker.processNewReviews(rules: rules)
// Alerts when rating drops
await reviewsWorker.monitorRating(threshold: 4.0)
```

## Technical Principles

### Swift 6 & Concurrency
- All workers are actors with isolation
- Sendable for all public types
- TaskGroup for parallel operations
- AsyncThrowingStream for pagination

### Security
- Minimal permissions for API keys
- Per-tool permissions in MCP
- Secrets via environment/Keychain
- Audit log for critical operations
- Dry-run mode for dangerous operations

### Performance
- Rate limiting per account
- Caching with ETag
- Field-sparse requests
- Include for minimizing requests
- Batch operations where possible

### Quality
- Contract tests with fixtures
- Integration tests with sandbox
- Fault injection (429/5xx/timeout)
- Structured logging
- Metrics and alerts

## Success Metrics

### Technical
- Test coverage > 80%
- Response time < 500ms (p95)
- Operation success rate > 99.5%
- Zero critical bugs in production

### Business
- Automate 90% of the release process
- Reduce release time by 70%
- Save 20+ hours per week on routine tasks
- Support 10+ teams simultaneously

## Next Steps

1. **Immediately**: Start with Phase 0 (platform)
2. **Week 1-2**: Implement the basic release pipeline
3. **Week 3-4**: Add TestFlight automation
4. **Month 2**: CI/CD provisioning and reviews
5. **Month 3**: Monetization and analytics

## Contacts and Resources

- [App Store Connect API Documentation](https://developer.apple.com/documentation/appstoreconnectapi)
- [JSON:API Specification](https://jsonapi.org)
- [Swift Concurrency Guide](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
