# App Store Connect MCP Server - Roadmap

## Архитектура и приоритеты

### 🔴 Критически важные функции

#### 1. Релизный пайплайн (AppLifecycleWorker)
- **AppStoreVersions**: создание версии, привязка билда, submit for review
- **Release Management**: manual/auto/scheduled release, phased rollout
- **Builds**: поиск по номеру, статус обработки, encryption declarations
- **Media Upload**: скриншоты, превью через uploadOperations

#### 2. TestFlight (TestFlightWorker)
- **Beta Groups & Testers**: управление группами и тестерами
- **Build Distribution**: привязка билдов к группам
- **Beta App Review**: подача на внешнее тестирование
- **Test Info & Localizations**: информация для тестеров

#### 3. Provisioning для CI/CD (ProvisioningWorker)
- **Devices**: регистрация UDID, batch операции
- **Certificates**: создание, ревокация
- **Profiles**: создание, регенерация
- **Bundle IDs & Capabilities**: управление идентификаторами

### 🟡 Важные функции

#### 4. Pricing & Availability (PricingWorker)
- **App Pricing**: цены и точки
- **Price Schedules**: планирование изменений
- **Territory Availability**: доступность по странам

#### 5. In-App Purchases & Subscriptions (IAPWorker)
- **IAP Management**: CRUD операций
- **Subscription Groups**: управление подписками
- **Offers & Promos**: промо-коды и предложения
- **Localization & Media**: локализации и медиа

#### 6. Customer Reviews (ReviewsWorker)
- **Review Fetching**: получение отзывов
- **Response Management**: ответы на отзывы
- **Auto-response Rules**: автоматические ответы
- **Analytics**: анализ и триаж

#### 7. Users & Access (UsersAccessWorker)
- **User Management**: управление пользователями
- **Invitations**: приглашения
- **Roles & Permissions**: роли и права

#### 8. Reporting (ReportingWorker)
- **Sales & Trends**: отчеты о продажах
- **Finance Reports**: финансовые отчеты
- **Metrics & Analytics**: метрики и аналитика

### 🟢 Полезные функции

#### 9. Xcode Cloud (XcodeCloudWorker)
- **Workflows**: управление CI/CD
- **Build Runs**: запуск и мониторинг
- **Artifacts**: артефакты сборок

#### 10. Game Center (GameCenterWorker)
- **Achievements**: достижения
- **Leaderboards**: таблицы лидеров
- **Localizations**: локализации

## Разделение на воркеры

📋 **[Детальный маппинг методов и API endpoints](./WORKERS_API_MAPPING.md)**

### Существующие (требуют рефакторинга)
```
AuthWorker (остается как есть + улучшения)
├── JWT кэширование (TTL ~20 мин)
├── Auto-refresh при 401
└── Clock skew handling

AppsWorker → разделить на:
├── AppCatalogWorker (листинг, поиск)
├── AppMetadataWorker (локализации, медиа)
└── AppLifecycleWorker (версии, релизы)
```

### Новые воркеры (по приоритету)
```
Фаза 1: Критические
├── AppLifecycleWorker
├── BuildWorker
├── TestFlightWorker
└── MediaUploadWorker

Фаза 2: CI/CD и отзывы
├── ProvisioningWorker
└── ReviewsWorker

Фаза 3: Монетизация
├── PricingWorker
└── IAPWorker

Фаза 4: Аналитика
├── ReportingWorker
└── WebhooksWorker

Фаза 5: Дополнительные
├── UsersAccessWorker
├── XcodeCloudWorker
├── GameCenterWorker
└── AlternativeDistributionWorker
```

### Общие сервисы (Services/)
```
Core Services
├── ASCClient (actor): HTTP client с JSON:API
├── RateLimiter: per-account rate limiting
├── Paginator: async stream pagination
├── ResourceCache: ETag/If-None-Match
├── MediaUploader: S3-like upload operations
├── ErrorMapper: единая таксономия ошибок
└── AuditLogger: логирование и трейсинг
```

## План реализации (Roadmap)

### Фаза 0: Платформа (1-2 недели)
- [ ] Рефакторинг ASCClient для JSON:API
- [ ] Реализация RateLimiter с token bucket
- [ ] Paginator с AsyncThrowingStream
- [ ] ResourceCache с ETag поддержкой
- [ ] ErrorMapper для единообразных ошибок
- [ ] Улучшение AuthWorker (кэш JWT)

### Фаза 1: Релизный контур ✅ ПОЛНОСТЬЮ ЗАВЕРШЕНА
- [x] **BuildsWorker** ✅
  - [x] Поиск билдов (`builds_list`, `builds_find_by_number`)
  - [x] Статусы обработки (`builds_get_processing_state`, `builds_wait_for_processing`)
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
- [x] **Технические улучшения** ✅
  - [x] SafeJSONHelpers - замена небезопасных `as Any`
  - [x] Structured JSON responses для всех методов
  - [x] Enhanced error handling для предотвращения MCP disconnections
  - [x] Type-safe optional handling

- [x] **AppLifecycleWorker** ✅ ЗАВЕРШЕН
  - [x] Создание версий (`app_versions_create`)
  - [x] Управление версиями (`app_versions_list`, `app_versions_get`, `app_versions_update`)
  - [x] Привязка билдов (`app_versions_attach_build`)
  - [x] Submit for review (`app_versions_submit_for_review`, `app_versions_cancel_review`)
  - [x] Release management (`app_versions_release`)
  - [x] Phased rollout (`app_versions_create_phased_release`, `app_versions_update_phased_release`)
  - [x] Review details (`app_versions_set_review_details`) - с автоматическим определением POST/PATCH
  - [x] Age rating (`app_versions_update_age_rating`) - с автоматическим определением POST/PATCH

### Фаза 2: CI/CD и отзывы ✅ ЗАВЕРШЕНА
- [x] **ProvisioningWorker** ✅
  - [x] Bundle IDs CRUD (`provisioning_list_bundle_ids`, `provisioning_get_bundle_id`, `provisioning_create_bundle_id`, `provisioning_delete_bundle_id`)
  - [x] Devices management (`provisioning_list_devices`, `provisioning_register_device`, `provisioning_update_device`)
  - [x] Certificates listing (`provisioning_list_certificates`)
  - [x] Profiles listing (`provisioning_list_profiles`)
- [x] **ReviewsWorker** ✅ (реализован ранее)
  - [x] Reviews listing, stats, filtering
  - [x] Response management
- [x] **BetaGroupsWorker** ✅
  - [x] Beta groups CRUD (`beta_groups_list`, `beta_groups_create`, `beta_groups_update`, `beta_groups_delete`)
  - [x] Testers management (`beta_groups_add_testers`, `beta_groups_remove_testers`)

### Фаза 3: Монетизация ✅ ЗАВЕРШЕНА
- [x] **InAppPurchasesWorker** ✅
  - [x] IAP CRUD (`iap_list`, `iap_get`, `iap_create`, `iap_update`, `iap_delete`)
  - [x] IAP Localizations (`iap_list_localizations`)
  - [x] Subscription groups (`iap_list_subscriptions`, `iap_get_subscription_group`)
- [ ] PricingWorker
  - [ ] Price points
  - [ ] Price schedules
  - [ ] Territory availability

### Фаза 4: Аналитика и события (1-2 недели)
- [ ] ReportingWorker
  - [ ] Sales reports
  - [ ] Finance reports
  - [ ] Metrics fetching
- [ ] WebhooksWorker
  - [ ] Event subscriptions
  - [ ] Delivery management
  - [ ] Retry logic

### Фаза 5: Дополнительные функции (по требованию)
- [ ] UsersAccessWorker
- [ ] XcodeCloudWorker
- [ ] GameCenterWorker
- [ ] AlternativeDistributionWorker

## Практические сценарии автоматизации

### Приоритет 1: One-click release
```swift
// Найти билд → создать версию → прикрепить → submit → release
let build = await buildWorker.findBuild(number: "1.2.3")
let version = await lifecycleWorker.createVersion(app: appId, version: "1.2.0")
await lifecycleWorker.attachBuild(version: version, build: build)
await lifecycleWorker.submitForReview(version: version)
await lifecycleWorker.release(version: version, type: .automatic)
```

### Приоритет 2: TestFlight automation
```swift
// Создать группу → добавить тестеров → назначить билд
let group = await testFlightWorker.createGroup(name: "External Beta")
await testFlightWorker.addTesters(group: group, emails: csvEmails)
await testFlightWorker.assignBuild(group: group, build: latestBuild)
```

### Приоритет 3: Provisioning as code
```swift
// Синхронизация из конфига
let config = ProvisioningConfig.load("provisioning.yml")
await provisioningWorker.sync(config: config)
// Авто-регенерация истекших
await provisioningWorker.regenerateExpired()
```

### Приоритет 4: Review management
```swift
// Авто-ответы по правилам
let rules = ReviewRules.load("review-rules.yml")
await reviewsWorker.processNewReviews(rules: rules)
// Алерты при падении рейтинга
await reviewsWorker.monitorRating(threshold: 4.0)
```

## Технические принципы

### Swift 6 & Concurrency
- Все воркеры - actors с изоляцией
- Sendable для всех публичных типов
- TaskGroup для параллельных операций
- AsyncThrowingStream для пагинации

### Безопасность
- Минимальные права для API ключей
- Per-tool permissions в MCP
- Секреты через environment/Keychain
- Аудит лог для критических операций
- Dry-run режим для опасных операций

### Производительность
- Rate limiting per account
- Кэширование с ETag
- Field-sparse запросы
- Include для минимизации запросов
- Batch операции где возможно

### Качество
- Контрактные тесты с фикстурами
- Интеграционные тесты с песочницей
- Fault injection (429/5xx/timeout)
- Structured logging
- Метрики и алерты

## Метрики успеха

### Технические
- Покрытие тестами > 80%
- Время ответа < 500ms (p95)
- Успешность операций > 99.5%
- Zero критических багов в проде

### Бизнес
- Автоматизация 90% релизного процесса
- Сокращение времени релиза на 70%
- Экономия 20+ часов в неделю на рутине
- Поддержка 10+ команд одновременно

## Следующие шаги

1. **Немедленно**: Начать с Фазы 0 (платформа)
2. **Неделя 1-2**: Реализовать базовый релизный контур
3. **Неделя 3-4**: Добавить TestFlight автоматизацию
4. **Месяц 2**: CI/CD provisioning и reviews
5. **Месяц 3**: Монетизация и аналитика

## Контакты и ресурсы

- [App Store Connect API Documentation](https://developer.apple.com/documentation/appstoreconnectapi)
- [JSON:API Specification](https://jsonapi.org)
- [Swift Concurrency Guide](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)