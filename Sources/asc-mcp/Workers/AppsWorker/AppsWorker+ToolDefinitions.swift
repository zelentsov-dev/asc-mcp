import Foundation
import MCP

// MARK: - Tool Definitions
extension AppsWorker {
    
    func listAppsTool() -> Tool {
        return Tool(
            name: "apps_list",
            description: "Получает список всех приложений из App Store Connect",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Максимальное количество приложений (по умолчанию 25)")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Сортировка: name, -name, bundleId, -bundleId")
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string("Фильтр по Bundle ID")
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Фильтр по имени приложения")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("URL следующей страницы из предыдущего ответа (поле next_url)")
                    ])
                ]),
                "required": .array([])
            ])
        )
    }

    func getAppDetailsTool() -> Tool {
        return Tool(
            name: "apps_get_details",
            description: "Получает детальную информацию о конкретном приложении",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("ID приложения в App Store Connect")
                    ]),
                    "include": .object([
                        "type": .string("string"),
                        "description": .string("Дополнительные связанные данные для включения")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }
    
    func listVersionsTool() -> Tool {
        return Tool(
            name: "apps_list_versions",
            description: "Получает список всех версий приложения с их ID и статусами",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("ID приложения в App Store Connect")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("URL следующей страницы из предыдущего ответа (поле next_url)")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func searchAppsTool() -> Tool {
        return Tool(
            name: "apps_search",
            description: "Поиск приложений по имени или Bundle ID",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Поисковый запрос (имя приложения или Bundle ID)")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    }
    
    func getAppMetadataTool() -> Tool {
        return Tool(
            name: "apps_get_metadata",
            description: """
                Получает метаданные приложения (описание, whatsNew, keywords и др.) для версии и локализации.

                Поведение:
                - Без locale: возвращает ВСЕ локали за один запрос
                - Без version_id: автоматически находит версию (приоритет: PREPARE_FOR_SUBMISSION > READY_FOR_SALE)
                - include_media: по умолчанию false, медиа загружается только по запросу
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("ID приложения в App Store Connect")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Код локали (en-US, ru-RU, de-DE). Если не указан — возвращает все локали")
                    ]),
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("ID версии приложения. Если не указан — автоматически выбирает подходящую версию")
                    ]),
                    "version_state": .object([
                        "type": .string("string"),
                        "description": .string("Фильтр состояния версии: PREPARE_FOR_SUBMISSION (редактируемая) или READY_FOR_SALE (опубликованная)")
                    ]),
                    "include_media": .object([
                        "type": .string("boolean"),
                        "description": .string("Включить скриншоты и видео в ответ (по умолчанию: false)")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    func updateMetadataTool() -> Tool {
        return Tool(
            name: "apps_update_metadata",
            description: "Обновляет метаданные версии приложения для конкретной локализации (версия должна быть в состоянии PREPARE_FOR_SUBMISSION)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("ID приложения в App Store Connect")
                    ]),
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("ID версии приложения (получить через apps_list_versions)")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Код локализации (например: 'en-US', 'ru-RU', 'de-DE', 'fr-FR', 'ja', 'zh-Hans')")
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("Описание приложения (до 4000 символов)")
                    ]),
                    "whats_new": .object([
                        "type": .string("string"),
                        "description": .string("What's New in This Version (до 4000 символов)")
                    ]),
                    "keywords": .object([
                        "type": .string("string"),
                        "description": .string("Ключевые слова через запятую (до 100 символов)")
                    ]),
                    "promotional_text": .object([
                        "type": .string("string"),
                        "description": .string("Промо-текст (до 170 символов)")
                    ]),
                    "support_url": .object([
                        "type": .string("string"),
                        "description": .string("URL поддержки")
                    ]),
                    "marketing_url": .object([
                        "type": .string("string"),
                        "description": .string("Маркетинговый URL")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("version_id"), .string("locale")])
            ])
        )
    }
    
    func createLocalizationTool() -> Tool {
        return Tool(
            name: "apps_create_localization",
            description: "Создает новую локализацию для версии приложения",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("ID версии приложения (получить через apps_list_versions)")
                    ]),
                    "locale": .object([
                        "type": .string("string"),
                        "description": .string("Код локализации (например: 'en-US', 'ru-RU', 'de-DE', 'fr-FR', 'ja', 'zh-Hans')")
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("Описание приложения (до 4000 символов)")
                    ]),
                    "whats_new": .object([
                        "type": .string("string"),
                        "description": .string("What's New in This Version (до 4000 символов)")
                    ]),
                    "keywords": .object([
                        "type": .string("string"),
                        "description": .string("Ключевые слова через запятую (до 100 символов)")
                    ]),
                    "promotional_text": .object([
                        "type": .string("string"),
                        "description": .string("Промо-текст (до 170 символов)")
                    ]),
                    "support_url": .object([
                        "type": .string("string"),
                        "description": .string("URL поддержки")
                    ]),
                    "marketing_url": .object([
                        "type": .string("string"),
                        "description": .string("Маркетинговый URL")
                    ])
                ]),
                "required": .array([.string("version_id"), .string("locale")])
            ])
        )
    }

    func deleteLocalizationTool() -> Tool {
        return Tool(
            name: "apps_delete_localization",
            description: "Удаляет локализацию версии приложения",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "localization_id": .object([
                        "type": .string("string"),
                        "description": .string("ID локализации для удаления (получить через apps_list_localizations)")
                    ])
                ]),
                "required": .array([.string("localization_id")])
            ])
        )
    }

    func listLocalizationsTool() -> Tool {
        return Tool(
            name: "apps_list_localizations",
            description: "Получает список всех локализаций для версии приложения",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("ID приложения в App Store Connect")
                    ]),
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("ID версии приложения")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("URL следующей страницы из предыдущего ответа (поле next_url)")
                    ])
                ]),
                "required": .array([.string("app_id"), .string("version_id")])
            ]
        )
    }
}