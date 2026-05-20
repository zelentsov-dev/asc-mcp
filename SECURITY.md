# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 2.5.x   | Yes       |
| 2.4.x   | Yes       |
| 2.3.x   | Yes       |
| 2.2.x   | Yes       |
| 2.1.x   | Yes       |
| 2.0.x   | Yes       |
| 1.x     | Security fixes only |
| < 1.0   | No        |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public issue**
2. Email: **fullback.94@gmail.com**
3. Include: description, reproduction steps, and impact assessment
4. You will receive a response within 48 hours

## Security Best Practices for Users

- **Never commit `.p8` private keys** to version control
- Use environment variables or a `companies.json` file outside your repo
- Add `companies.json`, `*.p8`, `*.pem`, `*.key` to your `.gitignore`
- Rotate App Store Connect API keys periodically
- Use `--workers` flag to limit exposed tools to only what you need
- JWT tokens are held in memory only and expire after 20 minutes
- Prefer read-only MCP smoke checks (`auth_generate_token`, `auth_token_status`, `apps_list limit=1`) after reloads
- Review tool annotations before approving high-risk actions such as submit, release, delete, revoke, clear, or cancel
