# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 4.1.x (latest stable: 4.1.6) | Supported stable line |
| 4.2.0 candidate | Under development; not approved for stable publication |
| < 4.1 | Upgrade to the supported stable line |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public issue**
2. Email: **fullback.94@gmail.com**
3. Include: description, reproduction steps, and impact assessment
4. Include the exact release/commit, operating system, and sanitized reproduction. Do not send API keys, JWTs, signed upload URLs, or customer files.

## Security Best Practices for Users

- **Never commit `.p8` private keys** to version control
- Use environment variables or a `companies.json` file outside your repo
- Add `companies.json`, `*.p8`, `*.pem`, `*.key` to your `.gitignore`
- Rotate App Store Connect API keys periodically
- Use `--workers` flag to limit exposed tools to only what you need
- JWT tokens are held in memory only and expire after 20 minutes
- Prefer read-only MCP smoke checks (`auth_generate_token`, `auth_token_status`, `apps_list limit=1`) after reloads
- Review tool annotations before approving high-risk actions such as submit, release, delete, revoke, clear, or cancel
- Use `--read-only` for inspection. Worker selection alone is not a write-permission boundary.
- Keep configuration files and `.p8` keys readable only by your user. The MCP server has the same local file access as the process that launches it; approve file paths deliberately.

## Asset Library write protocol (4.2.0 candidate)

All new Asset Library mutations require `assets_prepare_change` followed by `assets_apply_change` with only its opaque `preview_id`. A preview expires after ten minutes, is consumed once, and is bound to the account session, app, file fingerprint and remote state. An account switch or process restart invalidates it. The MCP client still controls human authorization; possession of a preview is not proof of approval.

Uploads use private snapshots of regular files, at most 2 GiB each. Preparation reserves capacity before copying: at most eight active preparations/previews/operations, a 4 GiB snapshot budget, and two concurrent transfers. Signed destinations come only from Apple's reservation response, use HTTPS, reject local/private network destinations and redirects, and never receive the ASC JWT. Asset transfers require the system `/usr/bin/curl` and `/usr/bin/dscacheutil`: DNS lookups run as cancellable child processes, with ten seconds per host, thirty seconds per reservation and at most two active lookups. Verified public addresses are pinned with `--resolve`, while the original hostname remains the TLS identity. URL and header secrets are supplied through stdin, with user curl configuration, proxies and automatic retries disabled. Upload response bodies are limited to 64 KiB. API responses and accumulated inventories for this worker are limited to 32 MiB; processing polls are bounded.

The private journal is stored in `~/.local/state/asc-mcp/asset-operations/<account fingerprint>/` with user-only directories and files. It records resource IDs, metadata fingerprints, requested changes and completed/uncertain steps. It does not persist private keys, JWTs, signed transfer URLs, headers, or file bytes. Treat app metadata and resource IDs as private nonetheless. Snapshots are discarded after execution or expiry. Completed records are pruned after seven days when admitting new work; uncertain operations are retained. A full or unsafe journal blocks new preparation.

An application lease prevents concurrent mutation or reconciliation of the same account/application across server processes. It does not lock App Store Connect against external users: preflight and readback detect relevant changes, but Apple's multi-step placement replacement is not atomic.

After a lost response, inspect `assets_get_operation`. The server does not replay an uncertain create, commit, delete or replacement. Resume only a confirmed reservation with the same file and a new preview. Partial replacement may leave a temporary gap in an editable draft; recovery is a separate explicit action. Deleting a placement does not delete the reusable asset, and deleting an asset never cascades through its placements.

Stable publication requires the candidate's automated checks, independent security review and authorized Apple acceptance. A successful build alone is not evidence of safe production operation.
