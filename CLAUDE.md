@AGENTS.md

## Claude Code specifics

- Build and test with `swift build` / `swift test`: this is a pure SwiftPM server package, the
  documented exception to the XcodeBuildMCP rule in the owner's Dev essentials.
- Production-effect App Store Connect tools (submit, release, phased release, pricing, availability,
  offers, review responses, certificate revocation, users) sit on the `ask` list of the Claude Code
  settings, so exercising them "as a real MCP" prompts the owner every time. Test with read tools
  and reversible calls first.
- `companies.json` and the `.p8` keys under `Keys/` are local secrets (gitignored): never print,
  quote or commit them; `companies.example.json` is the shareable shape.
