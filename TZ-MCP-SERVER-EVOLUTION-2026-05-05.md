# ТЗ 2. Развитие MCP-сервера `asc-mcp`

Дата: 2026-05-05

## 1. Цель

Определить, что стоит улучшить в самом MCP-сервере как продукте и инженерной платформе: не только добавить App Store Connect endpoints, а сделать сервер удобнее, безопаснее, быстрее и полезнее для реальной работы с релизами.

Короткий вердикт: текущую архитектуру после refactor не надо переписывать с нуля. Правильный путь — сохранить существующий Worker pattern и добавить поверх него несколько платформенных слоев: MCP Resources/Prompts/Completion/Logging, OpenAPI coverage tooling, safer write workflows, better observability, presets, generated docs and smoke harness.

## 2. Current State

Подтверждено локально:
- Tools capability включена.
- 293 tools в 32 worker domains.
- Tool annotations/_meta/structuredContent/outputSchema foundation уже заложены.
- Release build warning-clean.
- Upload, HTTP errors, rate limits, metadata validation и docs drift tests усилены.

Главный пробел:
- Сервер пока почти полностью tool-only. MCP 2025-11-25 поддерживает больше полезных возможностей: Resources, Prompts, Completion, Logging, Progress/Cancellation, Authorization for HTTP transport, Elicitation. Их не нужно добавлять все сразу, но именно они могут сделать `asc-mcp` удобным MCP-продуктом, а не просто набором сотен functions.

## 3. Official MCP Baseline

Использовать:
- MCP 2025-11-25 overview: https://modelcontextprotocol.io/specification/2025-11-25
- MCP Tools: https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- MCP Resources: https://modelcontextprotocol.io/specification/2025-11-25/server/resources
- MCP Prompts: https://modelcontextprotocol.io/specification/2025-11-25/server/prompts
- MCP Completion: https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/completion
- MCP Logging: https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/logging
- MCP Elicitation: https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation
- MCP Authorization: https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization
- Official Swift SDK: https://github.com/modelcontextprotocol/swift-sdk

Key MCP facts for this project:
- Tools are model-controlled and need strong safety metadata.
- Resources are application-controlled context, useful for stable state snapshots.
- Prompts are user-controlled workflows, useful for release/checklist flows.
- Completion can make IDs/locales/company names easier to enter.
- Logging lets server send structured log notifications instead of only stderr.
- Elicitation form mode must not request secrets; URL mode is the correct future path for sensitive auth flows.
- HTTP authorization is optional; stdio should keep env/config credentials.

## 4. Product Direction

### Recommended Positioning

`asc-mcp` should become:
- a production release assistant for App Store Connect;
- a read/write ASC API toolbox with safe mutation labeling;
- a release-readiness and TestFlight triage workflow server;
- a reporting/analytics helper;
- a protocol-correct MCP server with generated docs and predictable outputs.

It should not become:
- a generic ASC OpenAPI dump with thousands of low-level tools exposed by default;
- a remote hosted service that stores user private keys without a separate security design;
- a server that hides destructive App Store actions behind vague tool names.

## 5. Priority Backlog

### P0. OpenAPI-Driven Coverage and Docs System

Problem:
Manual worker/table maintenance will keep drifting as Apple releases new API versions.

Requirements:
- Add a script or Swift test helper to parse Apple OpenAPI spec.
- Generate:
  - endpoint inventory;
  - endpoint-to-tool coverage matrix;
  - docs/tool-count matrix;
  - missing endpoint report.
- Add CI check that README worker table and `getTools()` snapshots match.

Acceptance:
- `swift test` fails if README worker counts drift.
- Coverage artifact makes it obvious what is missing and why.

### P0. Resources Capability

Why:
Hundreds of tools consume context. Resources can expose stable read-only snapshots without expanding tool descriptions.

Proposed resources:
- `asc://companies`
- `asc://company/current`
- `asc://apps`
- `asc://apps/{app_id}`
- `asc://apps/{app_id}/versions`
- `asc://apps/{app_id}/release-readiness`
- `asc://apps/{app_id}/testflight/status`
- `asc://apps/{app_id}/reviews/summary`
- `asc://apps/{app_id}/analytics/summary`
- `asc://server/capabilities`
- `asc://server/tool-policy`

Implementation:
- Add `ResourcesManager`.
- Add `ListResources`, `ReadResource`, optional resource templates.
- Use custom URI scheme `asc://`.
- Keep data read-only and sanitized.
- Add resource annotations with audience/priority/lastModified where SDK supports it.

Acceptance:
- Client can list resources.
- Reading `asc://server/capabilities` returns current worker/tool counts and enabled worker filter.
- Reading app resources never mutates ASC.

### P0. Prompts Capability

Why:
Users often ask for workflows, not raw endpoint calls. Prompts can expose safe, repeatable workflows as user-selected commands.

Proposed prompts:
- `asc_release_readiness_check`
- `asc_prepare_testflight_notes`
- `asc_review_response_draft`
- `asc_metadata_audit`
- `asc_localization_completeness_check`
- `asc_price_change_plan`
- `asc_subscription_launch_checklist`
- `asc_testflight_feedback_triage`
- `asc_webhook_setup_plan`
- `asc_xcode_cloud_build_triage`

Prompt requirements:
- Prompts must not mutate by themselves.
- Prompts should tell the model which read-only tools/resources to call first.
- Prompts should explicitly mark where user approval is required before write tools.

Acceptance:
- `prompts/list` returns workflow prompts.
- `prompts/get` returns structured messages with arguments.
- README documents prompt examples.

### P0. Completion Capability

Why:
Most ASC calls require opaque IDs. Completion can reduce mistakes and improve UX.

Suggested completions:
- `company` from configured companies.
- `app_id` and `bundle_id` from `apps_list`.
- `platform`: IOS, MAC_OS, TV_OS, VISION_OS.
- `locale`: valid locale list used by Apple metadata.
- `version_id` from app versions.
- `build_id` from builds.
- `subscription_group_id`, `subscription_id`, `iap_id`.
- `territory_code`, `price_point_id`.

Constraints:
- Completion must be read-only.
- Cache results with short TTL to avoid rate-limit pressure.
- If no active company/token exists, return empty completions with useful message.

### P0. Safer Mutation Workflow

Problem:
Annotations help clients, but models can still call write tools if user prompt is vague.

Requirements:
- Add global CLI flag: `--read-only`.
  - In this mode all create/update/delete/upload/submit/release/send/revoke/clear/cancel tools return `isError: true`.
- Add optional `--allow-destructive` flag for destructive/high-risk tools if user wants hard local gate.
- Add per-tool `dry_run` for high-risk mutations where possible:
  - release/submit/cancel/delete/clear/revoke/send notification;
  - explain exact request that would be sent.
- Add structured `mutationPlan` in dry-run responses.

Acceptance:
- In `--read-only`, live smoke can safely expose server to agents.
- Tests verify destructive tools are blocked.

### P1. Structured MCP Logging

Why:
Current stderr logs are useful locally but not MCP-native. MCP logging gives clients severity, logger name and JSON data.

Requirements:
- Add `logging` capability if Swift SDK supports it.
- Keep stderr for process diagnostics.
- Emit MCP logs for:
  - company switch;
  - auth refresh;
  - ASC request retry;
  - rate-limit observation;
  - upload progress/failure;
  - validation failure;
  - destructive tool dry-run/blocked call.

Security:
- All logs must pass through `Redactor`.
- No JWT/private key/raw `.p8`/signed upload URL.

### P1. Progress and Cancellation

Why:
Uploads, analytics downloads, report parsing and future Xcode Cloud/build workflows can be long-running.

Requirements:
- Support progress tokens from `_meta.progressToken` where SDK exposes it.
- Emit progress for:
  - uploads by chunk;
  - report download/decompression/parse;
  - batch metadata operations;
  - future background assets uploads.
- Check cancellation between chunks/pages/batches.

Acceptance:
- Unit tests for cancellation-aware upload/report path.
- Manual MCP smoke can cancel a long-running fake/test tool without corrupting state.

### P1. Tool Discoverability and Presets

Problem:
293 tools is powerful but heavy. Adding more Apple domains can make context worse.

Requirements:
- Add worker presets:
  - `release`
  - `testflight`
  - `monetization`
  - `marketing`
  - `analytics`
  - `provisioning`
  - `xcode-cloud`
  - `game-center`
  - `readonly`
- CLI:
  - `--preset release`
  - `--workers apps,builds`
  - `--exclude-workers game_center,alt_distribution`
- Print enabled tools count at startup.
- README should recommend presets per client/tool-limit.

Acceptance:
- Preset tests assert exact enabled worker keys.
- No duplicate worker registration.

### P1. Generated Tool Documentation

Requirements:
- Generate `docs/TOOLS.md` from actual `getTools()`.
- Include:
  - tool name;
  - worker;
  - description;
  - input schema;
  - annotations;
  - outputSchema if present;
  - example minimal call.
- README links to generated docs instead of duplicating huge details.

Acceptance:
- `swift test` or script fails if generated docs are stale.

### P1. Protocol-Level Smoke Harness

Problem:
Unit tests do not fully prove behavior through real JSON-RPC/MCP protocol.

Requirements:
- Add local integration harness that starts `.build/debug/asc-mcp` over stdio.
- Calls:
  - initialize;
  - tools/list;
  - selected tool calls with fake/no network where possible;
  - resources/list after Resources support;
  - prompts/list after Prompts support.
- Add read-only live smoke script gated by env:
  - `auth_generate_token`;
  - `auth_token_status`;
  - `apps_list limit=1`;
  - future read-only tools.

Acceptance:
- CI runs non-live MCP protocol smoke.
- Live smoke is opt-in and never calls mutation tools.

### P1. Config and Secret UX

Requirements:
- Add `asc-mcp config validate --companies path`.
- Validate:
  - file exists;
  - private key path exists/readable;
  - key content looks like `.p8`;
  - issuer/key IDs format;
  - vendor number presence for analytics if analytics worker enabled.
- Add optional Keychain/1Password integration only after separate security design.

Hard rule:
- Do not request API keys/private keys through form-mode elicitation. MCP spec says sensitive data must not be requested through form mode; future remote auth should use URL mode or external vault.

### P1. Role and Capability Awareness

Problem:
Apple endpoints have role restrictions. Users need understandable failures before API call when possible.

Requirements:
- Add endpoint metadata:
  - required role families;
  - Team key vs Individual key support where known;
  - mutation/read-only;
  - version-state restrictions;
  - file upload requirements.
- `auth_token_status` should include safe key mode metadata if inferable.
- Tools should return helpful messages for likely role mismatch.

Acceptance:
- Docs include role notes for analytics/sales/finance, webhooks, accessibility, feedback.

### P2. HTTP Transport and Remote MCP

Recommendation:
Keep stdio as default. Add HTTP/remote only as a separate milestone because it changes security posture.

Requirements if implemented:
- Streamable HTTP transport.
- OAuth protected resource metadata for remote server.
- No local private key storage in hosted service unless encrypted vault design exists.
- Per-user company config isolation.
- Audit log per user/session.

Do not:
- Add remote server mode as a casual flag without auth, TLS and tenant isolation.

### P2. Elicitation

Good use cases:
- Ask for missing non-sensitive parameters:
  - app selection;
  - locale selection;
  - confirmation text;
  - release phased rollout choice.

Forbidden:
- Do not ask for API keys, private keys, access tokens, passwords or payment credentials through form mode.

Future:
- URL mode elicitation can support an external secure credential setup page or OAuth-like broker if the server becomes remote.

### P2. Resource Links and File Outputs

Use for:
- crash logs;
- analytics report raw TSV;
- screenshots from TestFlight feedback;
- generated coverage reports;
- upload manifests.

Requirements:
- Prefer resource links or local files over dumping huge content into text.
- Redact and bound outputs.
- Add `maxResultSizeChars` policy per heavy tool.

### P2. Caching and Rate-Limit Strategy

Requirements:
- Small TTL cache for read-heavy reference endpoints:
  - companies;
  - apps;
  - territories;
  - app categories;
  - price points;
  - Xcode/macOS versions.
- Cache must be per company and baseURL.
- Expose cache metadata in `_meta`.
- Add `--no-cache` and tool-level `refresh=true`.

Acceptance:
- Tests prove cache isolation by company.
- Rate-limit metadata remains accurate.

### P2. Architecture Hardening

Recommended refactors:
- Endpoint descriptor layer:
  - method;
  - path template;
  - resource family;
  - role hints;
  - mutation class;
  - validator;
  - response formatter.
- Generate repetitive list/get/create/update/delete handlers from descriptors where safe.
- Keep hand-written handlers for workflow tools and uploads.
- Move JSON dictionary formatting to typed DTO/result mappers.

Do not:
- Replace every worker with codegen at once. Start with new domains.

### P2. Security and Privacy Review

Required checks:
- Redaction test corpus:
  - JWT;
  - key ID;
  - issuer ID;
  - private key path;
  - signed upload URL;
  - tester email;
  - review author nickname if considered PII in summaries.
- SSRF protections for `next_url` and any webhook/upload URL handling.
- Output minimization for reviews, beta feedback and crash logs.
- Audit log for mutations.

### P3. Packaging and Release

Nice improvements:
- Homebrew tap formula in addition to Mint.
- Signed/notarized macOS binary release if distributing binaries.
- GitHub Release automation:
  - attach binary;
  - attach checksum;
  - include generated tool count;
  - include migration notes.
- `asc-mcp --version`.
- `asc-mcp doctor`.
- `asc-mcp list-workers`.
- `asc-mcp list-tools --worker apps --json`.

## 6. Recommended Implementation Roadmap

### Milestone A. Product and Protocol Foundation

Scope:
- Resources capability.
- Prompts capability.
- Completion capability.
- `--read-only`.
- Generated tool docs.
- Protocol smoke harness.

Why first:
This improves UX and safety before adding many more ASC tools.

Acceptance:
- Existing tools unchanged.
- `swift test` and MCP protocol smoke pass.
- README has resource/prompt examples.

### Milestone B. Observability and Long-Running Operations

Scope:
- MCP logging.
- Progress/cancellation.
- Mutation audit log.
- Better rate-limit cache/state reporting.

Acceptance:
- Upload/report paths report progress.
- Cancellation tests pass.
- Logs are redacted.

### Milestone C. ASC Coverage Expansion

Scope:
- OpenAPI coverage matrix.
- P0 ASC workers from ТЗ 1:
  - Webhooks;
  - Beta Feedback;
  - Accessibility Declarations.
- P1 worker selected by user priority:
  - Routing Coverage or Background Assets.

Acceptance:
- New workers are additive.
- Read-only live smoke only.

### Milestone D. Optional Heavy Domains

Scope:
- Xcode Cloud.
- Game Center.
- Alternative Distribution.

Acceptance:
- Disabled from recommended minimal presets unless requested.
- Full docs and safety gates.

## 7. Acceptance Criteria

- Existing 293 tools remain compatible.
- New MCP capabilities are additive and documented.
- `swift build`, release build, `swift test`, `git diff --check` pass.
- Release build has zero warnings.
- Generated docs and README cannot drift silently.
- Live validation stays read-only unless explicitly approved.
- Security docs explain stdio credentials vs future remote auth.

## 8. My Recommendation

Do not pause development and do not rewrite everything. The current server is already strong after the production refactor. The best next move is:

1. Add OpenAPI coverage matrix.
2. Add Resources/Prompts/Completion because they improve everyday user experience immediately.
3. Add `--read-only` and generated docs before more write tools.
4. Add ASC P0 domains: Webhooks, Beta Feedback, Accessibility.
5. Keep Xcode Cloud, Game Center and Alternative Distribution opt-in so default context does not become too heavy.
