# App Store Connect MCP - Workers API Mapping

## 🔴 AppLifecycleWorker ✅ РЕАЛИЗОВАН

Управление жизненным циклом версий приложения в App Store.

**Статус**: Полностью реализован с 12 методами

### Методы и API Endpoints

```swift
// 1. Создание новой версии
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

// 2. Получение версий приложения
func listVersions(appId: String, states: [VersionState]?) async
    GET /v1/apps/{appId}/appStoreVersions
    Query: filter[appStoreVersionState], include=build,appStoreVersionSubmission
    Returns: [AppStoreVersion]

// 3. Получение конкретной версии
func getVersion(versionId: String) async
    GET /v1/appStoreVersions/{versionId}
    Query: include=build,appStoreVersionSubmission,appStoreVersionPhasedRelease
    Returns: AppStoreVersion

// 4. Обновление версии
func updateVersion(versionId: String, attributes: VersionUpdateAttributes) async
    PATCH /v1/appStoreVersions/{versionId}
    Body: { "data": { "type": "appStoreVersions", "id": "{versionId}", "attributes": {...} } }
    Returns: AppStoreVersion

// 5. Привязка билда к версии
func attachBuild(versionId: String, buildId: String) async
    PATCH /v1/appStoreVersions/{versionId}/relationships/build
    Body: { "data": { "type": "builds", "id": "{buildId}" } }
    Returns: Success

// 6. Отправка на ревью
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

// 7. Отмена ревью
func cancelReview(submissionId: String) async
    DELETE /v1/appStoreVersionSubmissions/{submissionId}
    Returns: Success

// 8. Создание поэтапного релиза
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

// 9. Управление поэтапным релизом
func updatePhasedRelease(phasedReleaseId: String, state: PhasedReleaseState) async
    PATCH /v1/appStoreVersionPhasedReleases/{phasedReleaseId}
    Body: { "data": { "type": "appStoreVersionPhasedReleases", "id": "{id}", "attributes": { "phasedReleaseState": "ACTIVE" } } }
    Returns: AppStoreVersionPhasedRelease

// 10. Релиз версии
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

// 11. Установка деталей для ревью (с автоматическим определением POST/PATCH)
func setReviewDetails(versionId: String, contactInfo: ReviewContactInfo) async
    Сначала: GET /v1/appStoreVersions/{versionId}?include=appStoreReviewDetail
    Если существует:
        PATCH /v1/appStoreReviewDetails/{reviewDetailId}
    Если не существует:
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
            "relationships": { // только для POST
                "appStoreVersion": { "data": { "type": "appStoreVersions", "id": "{versionId}" } }
            }
        }
    }
    Returns: AppStoreReviewDetail

// 12. Управление возрастным рейтингом (с автоматическим определением POST/PATCH)
func updateAgeRating(versionId: String, declaration: AgeRatingDeclaration) async
    Сначала: GET /v1/appStoreVersions/{versionId}?include=ageRatingDeclaration
    Если существует:
        PATCH /v1/ageRatingDeclarations/{ageRatingId}
    Если не существует:
        POST /v1/ageRatingDeclarations
    Body: {
        "data": {
            "type": "ageRatingDeclarations",
            "attributes": {
                "alcoholTobaccoOrDrugUseOrReferences": "NONE",
                "violenceCartoonOrFantasy": "NONE",
                // ... другие атрибуты рейтинга
            },
            "relationships": { // только для POST
                "appStoreVersion": { "data": { "type": "appStoreVersions", "id": "{versionId}" } }
            }
        }
    }
    Returns: AgeRatingDeclaration
```

## 🔴 BuildsWorker ✅ РЕАЛИЗОВАН

Управление билдами приложения.

### Методы и API Endpoints

```swift
// ✅ РЕАЛИЗОВАНО
// 1. Получение списка билдов
func builds_list(appId: String, version?: String, processingState?: ProcessingState) async
    GET /v1/builds
    Query: filter[app]={appId}, filter[version], filter[processingState], include=app,buildBetaDetail,preReleaseVersion
    Returns: JSON с массивом билдов

// ✅ РЕАЛИЗОВАНО
// 2. Получение конкретного билда
func builds_get(buildId: String) async
    GET /v1/builds/{buildId}
    Query: include=app,buildBetaDetail,preReleaseVersion,buildBundles
    Returns: JSON с деталями билда

// ✅ РЕАЛИЗОВАНО
// 3. Поиск билда по номеру
func builds_find_by_number(appId: String, buildNumber: String) async
    GET /v1/builds
    Query: filter[app]={appId}, filter[version]={buildNumber}, limit=1
    Returns: JSON с найденным билдом или null

// ✅ РЕАЛИЗОВАНО
// 4. Список билдов для версии
func builds_list_for_version(versionId: String) async
    GET /v1/appStoreVersions/{versionId}/builds
    Returns: JSON с билдами для версии

// ✅ РЕАЛИЗОВАНО через BuildProcessingWorker
// 5. Получение статуса обработки
func builds_get_processing_state(buildId: String) async
    GET /v1/builds/{buildId}
    Query: fields[builds]=processingState,uploadedDate
    Returns: JSON со статусом обработки

// ✅ РЕАЛИЗОВАНО через BuildProcessingWorker
// 6. Ожидание завершения обработки
func builds_wait_for_processing(buildId: String, maxWaitSeconds: Int, pollIntervalSeconds: Int) async
    Периодические запросы GET /v1/builds/{buildId}
    Returns: JSON с финальным статусом

// ✅ РЕАЛИЗОВАНО через BuildProcessingWorker
// 7. Проверка готовности билда
func builds_check_readiness(buildId: String) async
    GET /v1/builds/{buildId} + комплексная проверка
    Returns: JSON со статусом готовности

// ✅ РЕАЛИЗОВАНО через BuildProcessingWorker
// 8. Обновление информации о шифровании
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
    Returns: JSON с обновленным билдом

// ✅ РЕАЛИЗОВАНО через BuildProcessingWorker
// 9. Установка срока действия билда
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
    Returns: JSON с результатом
```

## 🔴 BuildBetaDetailsWorker ✅ РЕАЛИЗОВАН

Управление TestFlight настройками билдов.

### Методы и API Endpoints

```swift
// ✅ РЕАЛИЗОВАНО
// 1. Получение бета-деталей билда
func builds_get_beta_detail(buildId: String) async
    GET /v1/builds/{buildId}/buildBetaDetail
    Returns: JSON с настройками TestFlight

// ✅ РЕАЛИЗОВАНО
// 2. Обновление бета-деталей
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
    Returns: JSON с обновленными настройками

// ✅ РЕАЛИЗОВАНО
// 3. Получение локализаций билда для TestFlight
func builds_list_beta_localizations(buildId: String) async
    GET /v1/builds/{buildId}/betaBuildLocalizations
    Returns: JSON с массивом локализаций

// ✅ РЕАЛИЗОВАНО
// 4. Установка What's New для TestFlight
func builds_set_beta_localization(buildId: String, locale: String, whatsNew: String) async
    GET /v1/builds/{buildId}/betaBuildLocalizations (поиск существующей)
    POST /v1/betaBuildLocalizations (создание) или PATCH (обновление)
    Returns: JSON с результатом

// ✅ РЕАЛИЗОВАНО (исправлен API endpoint)
// 5. Получение бета-групп для билда
func builds_get_beta_groups(buildId: String) async
    GET /v1/betaGroups?filter[builds]={buildId}
    Returns: JSON с массивом бета-групп

// ✅ РЕАЛИЗОВАНО
// 6. Получение бета-тестеров для билда
func builds_get_beta_testers(buildId: String) async
    GET /v1/builds/{buildId}/betaTesters
    Returns: JSON с массивом тестеров

// ✅ РЕАЛИЗОВАНО
// 7. Отправка уведомления тестерам
func builds_send_beta_notification(betaDetailId: String, locale?: String) async
    PATCH /v1/buildBetaDetails/{betaDetailId} + уведомление
    Returns: JSON с результатом
```

## 🔴 BuildProcessingWorker ✅ РЕАЛИЗОВАН

Управление состояниями обработки билдов.

### Методы и API Endpoints

```swift
// ✅ РЕАЛИЗОВАНО
// Все методы доступны через builds_* префикс в BuildsWorker
// Внутренняя логика в BuildProcessingWorker включает:

// 1. Мониторинг статуса обработки
// 2. Проверку готовности для submission
// 3. Управление encryption compliance
// 4. Контроль expiration dates
// 5. Валидацию состояний билда
```

## 🔴 TestFlightWorker

Управление бета-тестированием через TestFlight.

### Методы и API Endpoints

```swift
// 1. Создание бета-группы
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

// 2. Получение списка групп
func listBetaGroups(appId: String) async
    GET /v1/apps/{appId}/betaGroups
    Query: include=betaTesters,builds
    Returns: [BetaGroup]

// 3. Добавление тестеров в группу
func addTestersToGroup(groupId: String, testerIds: [String]) async
    POST /v1/betaGroups/{groupId}/relationships/betaTesters
    Body: {
        "data": [
            { "type": "betaTesters", "id": "{testerId1}" },
            { "type": "betaTesters", "id": "{testerId2}" }
        ]
    }
    Returns: Success

// 4. Создание бета-тестера
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

// 5. Приглашение тестеров
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

// 6. Привязка билда к группе
func assignBuildToGroup(groupId: String, buildId: String) async
    POST /v1/betaGroups/{groupId}/relationships/builds
    Body: {
        "data": [
            { "type": "builds", "id": "{buildId}" }
        ]
    }
    Returns: Success

// 7. Удаление тестера из группы
func removeTesterFromGroup(groupId: String, testerId: String) async
    DELETE /v1/betaGroups/{groupId}/relationships/betaTesters
    Body: {
        "data": [
            { "type": "betaTesters", "id": "{testerId}" }
        ]
    }
    Returns: Success

// 8. Подача на внешнее бета-тестирование
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

// 9. Получение статуса бета-ревью
func getBetaReviewStatus(submissionId: String) async
    GET /v1/betaAppReviewSubmissions/{submissionId}
    Returns: BetaAppReviewSubmission

// 10. Создание публичной ссылки
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

// 11. Установка локализации для билда
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

Управление сертификатами, профилями и устройствами.

### Методы и API Endpoints

```swift
// 1. Регистрация устройства
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

// 2. Получение списка устройств
func listDevices(status: DeviceStatus?, platform: Platform?) async
    GET /v1/devices
    Query: filter[status], filter[platform], limit=200
    Returns: [Device]

// 3. Обновление устройства
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

// 4. Создание сертификата
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

// 5. Получение списка сертификатов
func listCertificates(types: [CertificateType]?) async
    GET /v1/certificates
    Query: filter[certificateType], filter[serialNumber]
    Returns: [Certificate]

// 6. Ревокация сертификата
func revokeCertificate(certificateId: String) async
    DELETE /v1/certificates/{certificateId}
    Returns: Success

// 7. Создание профиля
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

// 8. Получение списка профилей
func listProfiles(profileState: ProfileState?, profileType: ProfileType?) async
    GET /v1/profiles
    Query: filter[profileState], filter[profileType], include=bundleId,certificates,devices
    Returns: [Profile]

// 9. Удаление профиля
func deleteProfile(profileId: String) async
    DELETE /v1/profiles/{profileId}
    Returns: Success

// 10. Создание Bundle ID
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

// 11. Управление capabilities
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

// 12. Удаление capability
func deleteCapability(capabilityId: String) async
    DELETE /v1/bundleIdCapabilities/{capabilityId}
    Returns: Success
```

## 🟡 ReviewsWorker

Управление отзывами пользователей.

### Методы и API Endpoints

```swift
// 1. Получение отзывов
func listReviews(appId: String, rating?: Int, territory?: String) async
    GET /v1/apps/{appId}/customerReviews
    Query: filter[rating], filter[territory], include=response, sort=-createdDate
    Returns: [CustomerReview]

// 2. Получение конкретного отзыва
func getReview(reviewId: String) async
    GET /v1/customerReviews/{reviewId}
    Query: include=response
    Returns: CustomerReview

// 3. Создание ответа на отзыв
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

// 4. Обновление ответа
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

// 5. Удаление ответа
func deleteResponse(responseId: String) async
    DELETE /v1/customerReviewResponses/{responseId}
    Returns: Success

// 6. Получение статистики отзывов
func getReviewSummary(appId: String) async
    GET /v1/apps/{appId}/customerReviewSummarizations
    Returns: CustomerReviewSummarization
```

## 🟡 PricingWorker

Управление ценами и доступностью.

### Методы и API Endpoints

```swift
// 1. Получение цен приложения
func getAppPricing(appId: String) async
    GET /v1/apps/{appId}/appPriceSchedule
    Query: include=appPrices,baseTerritory,manualPrices
    Returns: AppPriceSchedule

// 2. Установка цены
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

// 3. Получение ценовых точек
func listPricePoints(territory: String) async
    GET /v1/appPricePoints
    Query: filter[territory], include=priceTier,territory
    Returns: [AppPricePoint]

// 4. Управление доступностью по территориям
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

// 5. Получение списка территорий
func listTerritories() async
    GET /v1/territories
    Returns: [Territory]
```

## 🟡 IAPWorker

Управление внутренними покупками и подписками.

### Методы и API Endpoints

```swift
// 1. Создание внутренней покупки
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

// 2. Получение списка покупок
func listInAppPurchases(appId: String) async
    GET /v1/apps/{appId}/inAppPurchasesV2
    Query: include=appStoreReviewScreenshot,pricePoints
    Returns: [InAppPurchase]

// 3. Создание группы подписок
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

// 4. Создание подписки
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

// 5. Установка цен на подписку
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

// 6. Создание промо-предложения
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

// 7. Локализация IAP
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

// 8. Отправка IAP на ревью
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

Загрузка медиа-контента (скриншоты, превью).

### Методы и API Endpoints

```swift
// 1. Создание набора скриншотов
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

// 2. Инициализация загрузки скриншота
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

// 3. Загрузка файла на S3
func uploadToS3(uploadOperation: UploadOperation, fileData: Data) async
    PUT {uploadOperation.url}
    Headers: {
        "Content-Type": "{uploadOperation.requestHeaders.Content-Type}",
        // другие headers из uploadOperation.requestHeaders
    }
    Body: fileData
    Returns: Success

// 4. Подтверждение загрузки
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

// 5. Создание набора превью
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

// 6. Загрузка превью видео
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

// 7. Удаление скриншота
func deleteScreenshot(screenshotId: String) async
    DELETE /v1/appScreenshots/{screenshotId}
    Returns: Success

// 8. Изменение порядка скриншотов
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

Управление метаданными приложения.

### Методы и API Endpoints

```swift
// 1. Создание локализации версии
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

// 2. Обновление локализации
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

// 3. Получение информации о приложении
func getAppInfo(appId: String) async
    GET /v1/apps/{appId}/appInfos
    Query: include=primaryCategory,secondaryCategory,primarySubcategoryOne
    Returns: AppInfo

// 4. Обновление категорий
func updateCategories(appInfoId: String, primaryCategoryId: String, secondaryCategoryId?: String) async
    PATCH /v1/appInfos/{appInfoId}/relationships/primaryCategory
    Body: {
        "data": { "type": "appCategories", "id": "{categoryId}" }
    }
    Returns: Success

// 5. Локализация информации о приложении
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

## Общие параметры и фильтры

### Query Parameters (для GET запросов)
- `include`: Включить связанные ресурсы (например, `include=app,build`)
- `fields[resource]`: Ограничить поля ресурса (например, `fields[apps]=name,bundleId`)
- `filter[attribute]`: Фильтрация по атрибуту (например, `filter[platform]=IOS`)
- `sort`: Сортировка результатов (например, `sort=-uploadedDate`)
- `limit`: Ограничение количества результатов (максимум 200)
- `cursor`: Курсор для пагинации

### Общие HTTP Headers
```
Authorization: Bearer {JWT_TOKEN}
Content-Type: application/json
Accept: application/json
```

### Статус коды
- `200 OK`: Успешный GET/PATCH
- `201 Created`: Успешный POST
- `204 No Content`: Успешный DELETE
- `400 Bad Request`: Неверные параметры
- `401 Unauthorized`: Неверный или истекший токен
- `403 Forbidden`: Нет прав доступа
- `404 Not Found`: Ресурс не найден
- `409 Conflict`: Конфликт состояния
- `422 Unprocessable Entity`: Валидация не пройдена
- `429 Too Many Requests`: Превышен лимит запросов

### Rate Limiting
- Лимит: 3600 запросов в час на ключ
- Headers: `X-Rate-Limit-Remaining`, `X-Rate-Limit-Reset`
- При превышении: экспоненциальный backoff с jitter

## Примеры использования

### One-click release workflow
```swift
// 1. Найти последний билд
let builds = await buildWorker.listBuilds(appId: appId, processingState: .valid)
let latestBuild = builds.first!

// 2. Создать новую версию
let version = await lifecycleWorker.createVersion(
    appId: appId,
    platform: .ios,
    versionString: "1.2.0"
)

// 3. Привязать билд
await lifecycleWorker.attachBuild(versionId: version.id, buildId: latestBuild.id)

// 4. Установить метаданные
let localization = await metadataWorker.updateLocalization(
    localizationId: version.localizationId,
    attributes: LocalizationAttributes(
        whatsNew: "New features and bug fixes",
        description: "Updated description"
    )
)

// 5. Загрузить скриншоты
let screenshotSet = await mediaWorker.createScreenshotSet(
    versionLocalizationId: localization.id,
    displayType: .iPhone65
)
await mediaWorker.uploadScreenshot(setId: screenshotSet.id, file: screenshotFile)

// 6. Отправить на ревью
let submission = await lifecycleWorker.submitForReview(versionId: version.id)

// 7. После одобрения - релиз
await lifecycleWorker.releaseVersion(versionId: version.id)
```