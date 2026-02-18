# App Store Connect MCP - Workers API Mapping

## 🔴 AppLifecycleWorker ✅ IMPLEMENTED

Management of the application version lifecycle in the App Store.

**Status**: Fully implemented with 12 methods

### Methods and API Endpoints

```swift
// 1. Create a new version
func createVersion(appId: String, platform: Platform, versionString: String) async
    POST /v1/appStoreVersions
    Body: {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS", // IOS, MAC_OS, TV_OS
                "versionString": "1.2.0",
                "releaseType": "MANUAL" // MANUAL, AFTER_APPROVAL, SCHEDULED
            },
            "relationships": {
                "app": { "data": { "type": "apps", "id": "{appId}" } }
            }
        }
    }
    Returns: AppStoreVersion

// 2. Get app versions
func listVersions(appId: String, states: [VersionState]?) async
    GET /v1/apps/{appId}/appStoreVersions
    Query: filter[appStoreVersionState], include=build,appStoreVersionSubmission
    Returns: [AppStoreVersion]

// 3. Get a specific version
func getVersion(versionId: String) async
    GET /v1/appStoreVersions/{versionId}
    Query: include=build,appStoreVersionSubmission,appStoreVersionPhasedRelease
    Returns: AppStoreVersion

// 4. Update a version
func updateVersion(versionId: String, attributes: VersionUpdateAttributes) async
    PATCH /v1/appStoreVersions/{versionId}
    Body: { "data": { "type": "appStoreVersions", "id": "{versionId}", "attributes": {...} } }
    Returns: AppStoreVersion

// 5. Attach a build to a version
func attachBuild(versionId: String, buildId: String) async
    PATCH /v1/appStoreVersions/{versionId}/relationships/build
    Body: { "data": { "type": "builds", "id": "{buildId}" } }
    Returns: Success

// 6. Submit for review
func submitForReview(versionId: String) async
    POST /v1/appStoreVersionSubmissions
    Body: {
        "data": {
            "type": "appStoreVersionSubmissions",
            "relationships": {
                "appStoreVersion": { "data": { "type": "appStoreVersions", "id": "{versionId}" } }
            }
        }
    }
    Returns: AppStoreVersionSubmission

// 7. Cancel review
func cancelReview(submissionId: String) async
    DELETE /v1/appStoreVersionSubmissions/{submissionId}
    Returns: Success

// 8. Create a phased release
func createPhasedRelease(versionId: String, startDate: Date?) async
    POST /v1/appStoreVersionPhasedReleases
    Body: {
        "data": {
            "type": "appStoreVersionPhasedReleases",
            "attributes": {
                "phasedReleaseState": "INACTIVE"
            },
            "relationships": {
                "appStoreVersion": { "data": { "type": "appStoreVersions", "id": "{versionId}" } }
            }
        }
    }
    Returns: AppStoreVersionPhasedRelease

// 9. Manage phased release
func updatePhasedRelease(phasedReleaseId: String, state: PhasedReleaseState) async
    PATCH /v1/appStoreVersionPhasedReleases/{phasedReleaseId}
    Body: { "data": { "type": "appStoreVersionPhasedReleases", "id": "{id}", "attributes": { "phasedReleaseState": "ACTIVE" } } }
    Returns: AppStoreVersionPhasedRelease

// 10. Release a version
func releaseVersion(versionId: String) async
    POST /v1/appStoreVersionReleaseRequests
    Body: {
        "data": {
            "type": "appStoreVersionReleaseRequests",
            "relationships": {
                "appStoreVersion": { "data": { "type": "appStoreVersions", "id": "{versionId}" } }
            }
        }
    }
    Returns: AppStoreVersionReleaseRequest

// 11. Set review details (with automatic POST/PATCH detection)
func setReviewDetails(versionId: String, contactInfo: ReviewContactInfo) async
    First: GET /v1/appStoreVersions/{versionId}?include=appStoreReviewDetail
    If exists:
        PATCH /v1/appStoreReviewDetails/{reviewDetailId}
    If not exists:
        POST /v1/appStoreReviewDetails
    Body: {
        "data": {
            "type": "appStoreReviewDetails",
            "attributes": {
                "contactFirstName": "John",
                "contactLastName": "Doe",
                "contactPhone": "+1234567890",
                "contactEmail": "john@example.com",
                "demoAccountName": "demo",
                "demoAccountPassword": "password",
                "notes": "Review notes"
            },
            "relationships": { // only for POST
                "appStoreVersion": { "data": { "type": "appStoreVersions", "id": "{versionId}" } }
            }
        }
    }
    Returns: AppStoreReviewDetail

// 12. Manage age rating (with automatic POST/PATCH detection)
func updateAgeRating(versionId: String, declaration: AgeRatingDeclaration) async
    First: GET /v1/appStoreVersions/{versionId}?include=ageRatingDeclaration
    If exists:
        PATCH /v1/ageRatingDeclarations/{ageRatingId}
    If not exists:
        POST /v1/ageRatingDeclarations
    Body: {
        "data": {
            "type": "ageRatingDeclarations",
            "attributes": {
                "alcoholTobaccoOrDrugUseOrReferences": "NONE",
                "violenceCartoonOrFantasy": "NONE",
                // ... other rating attributes
            },
            "relationships": { // only for POST
                "appStoreVersion": { "data": { "type": "appStoreVersions", "id": "{versionId}" } }
            }
        }
    }
    Returns: AgeRatingDeclaration
```

## 🔴 BuildsWorker ✅ IMPLEMENTED

Management of application builds.

### Methods and API Endpoints

```swift
// ✅ IMPLEMENTED
// 1. Get list of builds
func builds_list(appId: String, version?: String, processingState?: ProcessingState) async
    GET /v1/builds
    Query: filter[app]={appId}, filter[version], filter[processingState], include=app,buildBetaDetail,preReleaseVersion
    Returns: JSON with array of builds

// ✅ IMPLEMENTED
// 2. Get a specific build
func builds_get(buildId: String) async
    GET /v1/builds/{buildId}
    Query: include=app,buildBetaDetail,preReleaseVersion,buildBundles
    Returns: JSON with build details

// ✅ IMPLEMENTED
// 3. Find build by number
func builds_find_by_number(appId: String, buildNumber: String) async
    GET /v1/builds
    Query: filter[app]={appId}, filter[version]={buildNumber}, limit=1
    Returns: JSON with found build or null

// ✅ IMPLEMENTED
// 4. List builds for a version
func builds_list_for_version(versionId: String) async
    GET /v1/appStoreVersions/{versionId}/builds
    Returns: JSON with builds for the version

// ✅ IMPLEMENTED via BuildProcessingWorker
// 5. Get processing state
func builds_get_processing_state(buildId: String) async
    GET /v1/builds/{buildId}
    Query: fields[builds]=processingState,uploadedDate
    Returns: JSON with processing state

// ✅ IMPLEMENTED via BuildProcessingWorker
// 6. Wait for processing completion
func builds_wait_for_processing(buildId: String, maxWaitSeconds: Int, pollIntervalSeconds: Int) async
    Periodic requests GET /v1/builds/{buildId}
    Returns: JSON with final state

// ✅ IMPLEMENTED via BuildProcessingWorker
// 7. Check build readiness
func builds_check_readiness(buildId: String) async
    GET /v1/builds/{buildId} + comprehensive check
    Returns: JSON with readiness status

// ✅ IMPLEMENTED via BuildProcessingWorker
// 8. Update encryption information
func builds_update_encryption(buildId: String, usesNonExemptEncryption: Bool) async
    PATCH /v1/builds/{buildId}
    Body: {
        "data": {
            "type": "builds",
            "id": "{buildId}",
            "attributes": {
                "usesNonExemptEncryption": false
            }
        }
    }
    Returns: JSON with updated build

// ✅ IMPLEMENTED via BuildProcessingWorker
// 9. Set build expiration
func builds_set_expiration(buildId: String, expireBuild: Bool) async
    PATCH /v1/builds/{buildId}
    Body: {
        "data": {
            "type": "builds",
            "id": "{buildId}",
            "attributes": {
                "expired": true
            }
        }
    }
    Returns: JSON with result
```

## 🔴 BuildBetaDetailsWorker ✅ IMPLEMENTED

Management of TestFlight build settings.

### Methods and API Endpoints

```swift
// ✅ IMPLEMENTED
// 1. Get beta details of a build
func builds_get_beta_detail(buildId: String) async
    GET /v1/builds/{buildId}/buildBetaDetail
    Returns: JSON with TestFlight settings

// ✅ IMPLEMENTED
// 2. Update beta details
func builds_update_beta_detail(betaDetailId: String, autoNotifyEnabled?: Bool) async
    PATCH /v1/buildBetaDetails/{betaDetailId}
    Body: {
        "data": {
            "type": "buildBetaDetails",
            "id": "{betaDetailId}",
            "attributes": {
                "autoNotifyEnabled": true
            }
        }
    }
    Returns: JSON with updated settings

// ✅ IMPLEMENTED
// 3. Get build localizations for TestFlight
func builds_list_beta_localizations(buildId: String) async
    GET /v1/builds/{buildId}/betaBuildLocalizations
    Returns: JSON with array of localizations

// ✅ IMPLEMENTED
// 4. Set What's New for TestFlight
func builds_set_beta_localization(buildId: String, locale: String, whatsNew: String) async
    GET /v1/builds/{buildId}/betaBuildLocalizations (search for existing)
    POST /v1/betaBuildLocalizations (create) or PATCH (update)
    Returns: JSON with result

// ✅ IMPLEMENTED (fixed API endpoint)
// 5. Get beta groups for a build
func builds_get_beta_groups(buildId: String) async
    GET /v1/betaGroups?filter[builds]={buildId}
    Returns: JSON with array of beta groups

// ✅ IMPLEMENTED
// 6. Get beta testers for a build
func builds_get_beta_testers(buildId: String) async
    GET /v1/builds/{buildId}/betaTesters
    Returns: JSON with array of testers

// ✅ IMPLEMENTED
// 7. Send notification to testers
func builds_send_beta_notification(betaDetailId: String, locale?: String) async
    PATCH /v1/buildBetaDetails/{betaDetailId} + notification
    Returns: JSON with result
```

## 🔴 BuildProcessingWorker ✅ IMPLEMENTED

Management of build processing states.

### Methods and API Endpoints

```swift
// ✅ IMPLEMENTED
// All methods are accessible via the builds_* prefix in BuildsWorker
// Internal logic in BuildProcessingWorker includes:

// 1. Processing state monitoring
// 2. Submission readiness check
// 3. Encryption compliance management
// 4. Expiration date control
// 5. Build state validation
```

## 🔴 TestFlightWorker

Management of beta testing through TestFlight.

### Methods and API Endpoints

```swift
// 1. Create a beta group
func createBetaGroup(appId: String, name: String, isInternalGroup: Bool) async
    POST /v1/betaGroups
    Body: {
        "data": {
            "type": "betaGroups",
            "attributes": {
                "name": "External Testers",
                "isInternalGroup": false,
                "publicLinkEnabled": true,
                "publicLinkLimit": 10000
            },
            "relationships": {
                "app": { "data": { "type": "apps", "id": "{appId}" } }
            }
        }
    }
    Returns: BetaGroup

// 2. Get list of groups
func listBetaGroups(appId: String) async
    GET /v1/apps/{appId}/betaGroups
    Query: include=betaTesters,builds
    Returns: [BetaGroup]

// 3. Add testers to a group
func addTestersToGroup(groupId: String, testerIds: [String]) async
    POST /v1/betaGroups/{groupId}/relationships/betaTesters
    Body: {
        "data": [
            { "type": "betaTesters", "id": "{testerId1}" },
            { "type": "betaTesters", "id": "{testerId2}" }
        ]
    }
    Returns: Success

// 4. Create a beta tester
func createBetaTester(email: String, firstName: String, lastName: String) async
    POST /v1/betaTesters
    Body: {
        "data": {
            "type": "betaTesters",
            "attributes": {
                "email": "tester@example.com",
                "firstName": "John",
                "lastName": "Doe"
            }
        }
    }
    Returns: BetaTester

// 5. Invite testers
func inviteTesters(groupId: String) async
    POST /v1/betaTesterInvitations
    Body: {
        "data": {
            "type": "betaTesterInvitations",
            "relationships": {
                "betaGroup": { "data": { "type": "betaGroups", "id": "{groupId}" } },
                "app": { "data": { "type": "apps", "id": "{appId}" } }
            }
        }
    }
    Returns: BetaTesterInvitation

// 6. Assign a build to a group
func assignBuildToGroup(groupId: String, buildId: String) async
    POST /v1/betaGroups/{groupId}/relationships/builds
    Body: {
        "data": [
            { "type": "builds", "id": "{buildId}" }
        ]
    }
    Returns: Success

// 7. Remove a tester from a group
func removeTesterFromGroup(groupId: String, testerId: String) async
    DELETE /v1/betaGroups/{groupId}/relationships/betaTesters
    Body: {
        "data": [
            { "type": "betaTesters", "id": "{testerId}" }
        ]
    }
    Returns: Success

// 8. Submit for external beta testing
func submitForBetaReview(buildId: String) async
    POST /v1/betaAppReviewSubmissions
    Body: {
        "data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {
                "build": { "data": { "type": "builds", "id": "{buildId}" } }
            }
        }
    }
    Returns: BetaAppReviewSubmission

// 9. Get beta review status
func getBetaReviewStatus(submissionId: String) async
    GET /v1/betaAppReviewSubmissions/{submissionId}
    Returns: BetaAppReviewSubmission

// 10. Create a public link
func createPublicLink(groupId: String, limit: Int) async
    PATCH /v1/betaGroups/{groupId}
    Body: {
        "data": {
            "type": "betaGroups",
            "id": "{groupId}",
            "attributes": {
                "publicLinkEnabled": true,
                "publicLinkLimit": 1000,
                "publicLinkLimitEnabled": true
            }
        }
    }
    Returns: BetaGroup

// 11. Set build localization
func setBuildLocalization(buildId: String, locale: String, whatsNew: String) async
    POST /v1/betaBuildLocalizations
    Body: {
        "data": {
            "type": "betaBuildLocalizations",
            "attributes": {
                "locale": "en-US",
                "whatsNew": "Bug fixes and improvements"
            },
            "relationships": {
                "build": { "data": { "type": "builds", "id": "{buildId}" } }
            }
        }
    }
    Returns: BetaBuildLocalization
```

## 🔴 ProvisioningWorker

Management of certificates, profiles, and devices.

### Methods and API Endpoints

```swift
// 1. Register a device
func registerDevice(name: String, udid: String, platform: Platform) async
    POST /v1/devices
    Body: {
        "data": {
            "type": "devices",
            "attributes": {
                "name": "John's iPhone",
                "udid": "00008030-001234567890ABCD",
                "platform": "IOS" // IOS, MAC_OS
            }
        }
    }
    Returns: Device

// 2. Get list of devices
func listDevices(status: DeviceStatus?, platform: Platform?) async
    GET /v1/devices
    Query: filter[status], filter[platform], limit=200
    Returns: [Device]

// 3. Update a device
func updateDevice(deviceId: String, name: String?, status: DeviceStatus?) async
    PATCH /v1/devices/{deviceId}
    Body: {
        "data": {
            "type": "devices",
            "id": "{deviceId}",
            "attributes": {
                "name": "New Name",
                "status": "DISABLED"
            }
        }
    }
    Returns: Device

// 4. Create a certificate
func createCertificate(csrContent: String, certificateType: CertificateType) async
    POST /v1/certificates
    Body: {
        "data": {
            "type": "certificates",
            "attributes": {
                "csrContent": "{base64_csr}",
                "certificateType": "IOS_DEVELOPMENT" // IOS_DEVELOPMENT, IOS_DISTRIBUTION, etc.
            }
        }
    }
    Returns: Certificate

// 5. Get list of certificates
func listCertificates(types: [CertificateType]?) async
    GET /v1/certificates
    Query: filter[certificateType], filter[serialNumber]
    Returns: [Certificate]

// 6. Revoke a certificate
func revokeCertificate(certificateId: String) async
    DELETE /v1/certificates/{certificateId}
    Returns: Success

// 7. Create a profile
func createProfile(name: String, type: ProfileType, bundleId: String, certificateIds: [String], deviceIds: [String]?) async
    POST /v1/profiles
    Body: {
        "data": {
            "type": "profiles",
            "attributes": {
                "name": "Development Profile",
                "profileType": "IOS_APP_DEVELOPMENT"
            },
            "relationships": {
                "bundleId": { "data": { "type": "bundleIds", "id": "{bundleId}" } },
                "certificates": { "data": [{ "type": "certificates", "id": "{certId}" }] },
                "devices": { "data": [{ "type": "devices", "id": "{deviceId}" }] }
            }
        }
    }
    Returns: Profile

// 8. Get list of profiles
func listProfiles(profileState: ProfileState?, profileType: ProfileType?) async
    GET /v1/profiles
    Query: filter[profileState], filter[profileType], include=bundleId,certificates,devices
    Returns: [Profile]

// 9. Delete a profile
func deleteProfile(profileId: String) async
    DELETE /v1/profiles/{profileId}
    Returns: Success

// 10. Create a Bundle ID
func createBundleId(identifier: String, name: String, platform: Platform) async
    POST /v1/bundleIds
    Body: {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": "com.example.app",
                "name": "Example App",
                "platform": "IOS"
            }
        }
    }
    Returns: BundleId

// 11. Manage capabilities
func updateCapabilities(bundleIdId: String, capabilities: [Capability]) async
    POST /v1/bundleIdCapabilities
    Body: {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {
                "capabilityType": "PUSH_NOTIFICATIONS",
                "settings": []
            },
            "relationships": {
                "bundleId": { "data": { "type": "bundleIds", "id": "{bundleIdId}" } }
            }
        }
    }
    Returns: BundleIdCapability

// 12. Delete a capability
func deleteCapability(capabilityId: String) async
    DELETE /v1/bundleIdCapabilities/{capabilityId}
    Returns: Success
```

## 🟡 ReviewsWorker

Management of user reviews.

### Methods and API Endpoints

```swift
// 1. Get reviews
func listReviews(appId: String, rating?: Int, territory?: String) async
    GET /v1/apps/{appId}/customerReviews
    Query: filter[rating], filter[territory], include=response, sort=-createdDate
    Returns: [CustomerReview]

// 2. Get a specific review
func getReview(reviewId: String) async
    GET /v1/customerReviews/{reviewId}
    Query: include=response
    Returns: CustomerReview

// 3. Create a response to a review
func createResponse(reviewId: String, responseBody: String) async
    POST /v1/customerReviewResponses
    Body: {
        "data": {
            "type": "customerReviewResponses",
            "attributes": {
                "responseBody": "Thank you for your feedback!"
            },
            "relationships": {
                "review": { "data": { "type": "customerReviews", "id": "{reviewId}" } }
            }
        }
    }
    Returns: CustomerReviewResponse

// 4. Update a response
func updateResponse(responseId: String, responseBody: String) async
    PATCH /v1/customerReviewResponses/{responseId}
    Body: {
        "data": {
            "type": "customerReviewResponses",
            "id": "{responseId}",
            "attributes": {
                "responseBody": "Updated response"
            }
        }
    }
    Returns: CustomerReviewResponse

// 5. Delete a response
func deleteResponse(responseId: String) async
    DELETE /v1/customerReviewResponses/{responseId}
    Returns: Success

// 6. Get review statistics
func getReviewSummary(appId: String) async
    GET /v1/apps/{appId}/customerReviewSummarizations
    Returns: CustomerReviewSummarization
```

## 🟡 PricingWorker

Management of pricing and availability.

### Methods and API Endpoints

```swift
// 1. Get app pricing
func getAppPricing(appId: String) async
    GET /v1/apps/{appId}/appPriceSchedule
    Query: include=appPrices,baseTerritory,manualPrices
    Returns: AppPriceSchedule

// 2. Set price
func setAppPrice(appId: String, priceTier: String, startDate: Date?) async
    POST /v1/appPriceSchedules
    Body: {
        "data": {
            "type": "appPriceSchedules",
            "relationships": {
                "app": { "data": { "type": "apps", "id": "{appId}" } },
                "manualPrices": {
                    "data": [{
                        "type": "appPrices",
                        "attributes": {
                            "startDate": "2024-01-01",
                            "endDate": null
                        },
                        "relationships": {
                            "appPricePoint": {
                                "data": { "type": "appPricePoints", "id": "{pricePointId}" }
                            }
                        }
                    }]
                }
            }
        }
    }
    Returns: AppPriceSchedule

// 3. Get price points
func listPricePoints(territory: String) async
    GET /v1/appPricePoints
    Query: filter[territory], include=priceTier,territory
    Returns: [AppPricePoint]

// 4. Manage territory availability
func updateTerritoryAvailability(appId: String, availableTerritories: [String], preOrderTerritories: [String]?) async
    PATCH /v1/apps/{appId}/appAvailabilities
    Body: {
        "data": {
            "type": "appAvailabilities",
            "attributes": {
                "availableInNewTerritories": true
            },
            "relationships": {
                "availableTerritories": {
                    "data": [
                        { "type": "territories", "id": "USA" },
                        { "type": "territories", "id": "CAN" }
                    ]
                }
            }
        }
    }
    Returns: AppAvailability

// 5. Get list of territories
func listTerritories() async
    GET /v1/territories
    Returns: [Territory]
```

## 🟡 IAPWorker

Management of in-app purchases and subscriptions.

### Methods and API Endpoints

```swift
// 1. Create an in-app purchase
func createInAppPurchase(appId: String, productId: String, type: IAPType, referenceName: String) async
    POST /v1/inAppPurchasesV2
    Body: {
        "data": {
            "type": "inAppPurchases",
            "attributes": {
                "productId": "com.example.premium",
                "inAppPurchaseType": "CONSUMABLE", // CONSUMABLE, NON_CONSUMABLE, AUTO_RENEWABLE_SUBSCRIPTION
                "referenceName": "Premium Feature"
            },
            "relationships": {
                "app": { "data": { "type": "apps", "id": "{appId}" } }
            }
        }
    }
    Returns: InAppPurchase

// 2. Get list of purchases
func listInAppPurchases(appId: String) async
    GET /v1/apps/{appId}/inAppPurchasesV2
    Query: include=appStoreReviewScreenshot,pricePoints
    Returns: [InAppPurchase]

// 3. Create a subscription group
func createSubscriptionGroup(appId: String, referenceName: String) async
    POST /v1/subscriptionGroups
    Body: {
        "data": {
            "type": "subscriptionGroups",
            "attributes": {
                "referenceName": "Premium Subscriptions"
            },
            "relationships": {
                "app": { "data": { "type": "apps", "id": "{appId}" } }
            }
        }
    }
    Returns: SubscriptionGroup

// 4. Create a subscription
func createSubscription(groupId: String, productId: String, referenceName: String) async
    POST /v1/subscriptions
    Body: {
        "data": {
            "type": "subscriptions",
            "attributes": {
                "productId": "com.example.monthly",
                "referenceName": "Monthly Subscription"
            },
            "relationships": {
                "group": { "data": { "type": "subscriptionGroups", "id": "{groupId}" } }
            }
        }
    }
    Returns: Subscription

// 5. Set subscription pricing
func setSubscriptionPricing(subscriptionId: String, pricePointId: String, territory: String) async
    POST /v1/subscriptionPrices
    Body: {
        "data": {
            "type": "subscriptionPrices",
            "attributes": {
                "preserveCurrentPrice": false,
                "startDate": null
            },
            "relationships": {
                "subscription": { "data": { "type": "subscriptions", "id": "{subscriptionId}" } },
                "subscriptionPricePoint": { "data": { "type": "subscriptionPricePoints", "id": "{pricePointId}" } }
            }
        }
    }
    Returns: SubscriptionPrice

// 6. Create a promotional offer
func createPromotionalOffer(subscriptionId: String, offerCode: String, duration: String, numberOfPeriods: Int) async
    POST /v1/subscriptionPromotionalOffers
    Body: {
        "data": {
            "type": "subscriptionPromotionalOffers",
            "attributes": {
                "offerCode": "PROMO2024",
                "duration": "ONE_MONTH",
                "numberOfPeriods": 3
            },
            "relationships": {
                "subscription": { "data": { "type": "subscriptions", "id": "{subscriptionId}" } },
                "prices": { "data": [{ "type": "subscriptionPromotionalOfferPrices", "id": "{priceId}" }] }
            }
        }
    }
    Returns: SubscriptionPromotionalOffer

// 7. Localize an IAP
func localizeInAppPurchase(iapId: String, locale: String, name: String, description: String) async
    POST /v1/inAppPurchaseLocalizations
    Body: {
        "data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {
                "locale": "en-US",
                "name": "Premium Feature",
                "description": "Unlock all premium features"
            },
            "relationships": {
                "inAppPurchase": { "data": { "type": "inAppPurchases", "id": "{iapId}" } }
            }
        }
    }
    Returns: InAppPurchaseLocalization

// 8. Submit IAP for review
func submitIAPForReview(iapId: String) async
    POST /v1/inAppPurchaseSubmissions
    Body: {
        "data": {
            "type": "inAppPurchaseSubmissions",
            "relationships": {
                "inAppPurchaseV2": { "data": { "type": "inAppPurchases", "id": "{iapId}" } }
            }
        }
    }
    Returns: InAppPurchaseSubmission
```

## 🔴 MediaUploadWorker

Uploading media content (screenshots, previews).

### Methods and API Endpoints

```swift
// 1. Create a screenshot set
func createScreenshotSet(versionLocalizationId: String, displayType: ScreenshotDisplayType) async
    POST /v1/appScreenshotSets
    Body: {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {
                "screenshotDisplayType": "APP_IPHONE_67" // APP_IPHONE_55, APP_IPHONE_65, APP_IPAD_PRO_129, etc.
            },
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": { "type": "appStoreVersionLocalizations", "id": "{localizationId}" }
                }
            }
        }
    }
    Returns: AppScreenshotSet

// 2. Initialize screenshot upload
func initializeScreenshotUpload(screenshotSetId: String, fileName: String, fileSize: Int) async
    POST /v1/appScreenshots
    Body: {
        "data": {
            "type": "appScreenshots",
            "attributes": {
                "fileName": "screenshot1.png",
                "fileSize": 1024000
            },
            "relationships": {
                "appScreenshotSet": {
                    "data": { "type": "appScreenshotSets", "id": "{screenshotSetId}" }
                }
            }
        }
    }
    Returns: AppScreenshot (with uploadOperations)

// 3. Upload file to S3
func uploadToS3(uploadOperation: UploadOperation, fileData: Data) async
    PUT {uploadOperation.url}
    Headers: {
        "Content-Type": "{uploadOperation.requestHeaders.Content-Type}",
        // other headers from uploadOperation.requestHeaders
    }
    Body: fileData
    Returns: Success

// 4. Confirm upload
func commitScreenshotUpload(screenshotId: String, uploaded: Bool, sourceFileChecksum: String) async
    PATCH /v1/appScreenshots/{screenshotId}
    Body: {
        "data": {
            "type": "appScreenshots",
            "id": "{screenshotId}",
            "attributes": {
                "uploaded": true,
                "sourceFileChecksum": "{md5_checksum}"
            }
        }
    }
    Returns: AppScreenshot

// 5. Create a preview set
func createPreviewSet(versionLocalizationId: String, previewType: PreviewType) async
    POST /v1/appPreviewSets
    Body: {
        "data": {
            "type": "appPreviewSets",
            "attributes": {
                "previewType": "IPHONE_67"
            },
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": { "type": "appStoreVersionLocalizations", "id": "{localizationId}" }
                }
            }
        }
    }
    Returns: AppPreviewSet

// 6. Upload preview video
func uploadPreview(previewSetId: String, fileName: String, fileSize: Int) async
    POST /v1/appPreviews
    Body: {
        "data": {
            "type": "appPreviews",
            "attributes": {
                "fileName": "preview.mp4",
                "fileSize": 10240000,
                "mimeType": "video/mp4"
            },
            "relationships": {
                "appPreviewSet": {
                    "data": { "type": "appPreviewSets", "id": "{previewSetId}" }
                }
            }
        }
    }
    Returns: AppPreview (with uploadOperations)

// 7. Delete a screenshot
func deleteScreenshot(screenshotId: String) async
    DELETE /v1/appScreenshots/{screenshotId}
    Returns: Success

// 8. Reorder screenshots
func reorderScreenshots(screenshotSetId: String, screenshotIds: [String]) async
    PATCH /v1/appScreenshotSets/{screenshotSetId}/relationships/appScreenshots
    Body: {
        "data": [
            { "type": "appScreenshots", "id": "{screenshot1Id}" },
            { "type": "appScreenshots", "id": "{screenshot2Id}" }
        ]
    }
    Returns: Success
```

## 🟡 AppMetadataWorker

Management of application metadata.

### Methods and API Endpoints

```swift
// 1. Create a version localization
func createVersionLocalization(versionId: String, locale: String) async
    POST /v1/appStoreVersionLocalizations
    Body: {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {
                "locale": "en-US"
            },
            "relationships": {
                "appStoreVersion": {
                    "data": { "type": "appStoreVersions", "id": "{versionId}" }
                }
            }
        }
    }
    Returns: AppStoreVersionLocalization

// 2. Update a localization
func updateLocalization(localizationId: String, attributes: LocalizationAttributes) async
    PATCH /v1/appStoreVersionLocalizations/{localizationId}
    Body: {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": "{localizationId}",
            "attributes": {
                "description": "App description",
                "keywords": "game,puzzle,fun",
                "marketingUrl": "https://example.com",
                "promotionalText": "Limited time offer!",
                "supportUrl": "https://example.com/support",
                "whatsNew": "Bug fixes and improvements"
            }
        }
    }
    Returns: AppStoreVersionLocalization

// 3. Get app information
func getAppInfo(appId: String) async
    GET /v1/apps/{appId}/appInfos
    Query: include=primaryCategory,secondaryCategory,primarySubcategoryOne
    Returns: AppInfo

// 4. Update categories
func updateCategories(appInfoId: String, primaryCategoryId: String, secondaryCategoryId?: String) async
    PATCH /v1/appInfos/{appInfoId}/relationships/primaryCategory
    Body: {
        "data": { "type": "appCategories", "id": "{categoryId}" }
    }
    Returns: Success

// 5. Localize app information
func updateAppInfoLocalization(appInfoLocalizationId: String, name: String, subtitle: String, privacyText: String) async
    PATCH /v1/appInfoLocalizations/{appInfoLocalizationId}
    Body: {
        "data": {
            "type": "appInfoLocalizations",
            "id": "{appInfoLocalizationId}",
            "attributes": {
                "name": "My App",
                "subtitle": "The best app ever",
                "privacyPolicyText": "Privacy policy text",
                "privacyPolicyUrl": "https://example.com/privacy"
            }
        }
    }
    Returns: AppInfoLocalization
```

## Common Parameters and Filters

### Query Parameters (for GET requests)
- `include`: Include related resources (e.g., `include=app,build`)
- `fields[resource]`: Limit resource fields (e.g., `fields[apps]=name,bundleId`)
- `filter[attribute]`: Filter by attribute (e.g., `filter[platform]=IOS`)
- `sort`: Sort results (e.g., `sort=-uploadedDate`)
- `limit`: Limit the number of results (maximum 200)
- `cursor`: Cursor for pagination

### Common HTTP Headers
```
Authorization: Bearer {JWT_TOKEN}
Content-Type: application/json
Accept: application/json
```

### Status Codes
- `200 OK`: Successful GET/PATCH
- `201 Created`: Successful POST
- `204 No Content`: Successful DELETE
- `400 Bad Request`: Invalid parameters
- `401 Unauthorized`: Invalid or expired token
- `403 Forbidden`: Access denied
- `404 Not Found`: Resource not found
- `409 Conflict`: State conflict
- `422 Unprocessable Entity`: Validation failed
- `429 Too Many Requests`: Rate limit exceeded

### Rate Limiting
- Limit: 3600 requests per hour per key
- Headers: `X-Rate-Limit-Remaining`, `X-Rate-Limit-Reset`
- On exceeding: exponential backoff with jitter

## Usage Examples

### One-click release workflow
```swift
// 1. Find the latest build
let builds = await buildWorker.listBuilds(appId: appId, processingState: .valid)
let latestBuild = builds.first!

// 2. Create a new version
let version = await lifecycleWorker.createVersion(
    appId: appId,
    platform: .ios,
    versionString: "1.2.0"
)

// 3. Attach the build
await lifecycleWorker.attachBuild(versionId: version.id, buildId: latestBuild.id)

// 4. Set metadata
let localization = await metadataWorker.updateLocalization(
    localizationId: version.localizationId,
    attributes: LocalizationAttributes(
        whatsNew: "New features and bug fixes",
        description: "Updated description"
    )
)

// 5. Upload screenshots
let screenshotSet = await mediaWorker.createScreenshotSet(
    versionLocalizationId: localization.id,
    displayType: .iPhone65
)
await mediaWorker.uploadScreenshot(setId: screenshotSet.id, file: screenshotFile)

// 6. Submit for review
let submission = await lifecycleWorker.submitForReview(versionId: version.id)

// 7. After approval - release
await lifecycleWorker.releaseVersion(versionId: version.id)
```
