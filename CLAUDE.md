@AGENTS.md

## Claude Code specifics

- Build and test with `swift build` / `swift test`: this is a pure SwiftPM server package, the
  documented exception to the XcodeBuildMCP rule (the owner's Dev essentials and the
  `swift-build-discipline` skill).
- Treat every write against a real App Store Connect company as live and owner-only unless it is
  provably reversible. The `ask` list of the Claude Code settings prompts the owner for the main
  production families (submit, release, phased release, pricing, availability, offers, review
  responses, certificate revocation, users, product page experiments, custom page visibility,
  accessibility publishing), but it is not exhaustive. Test with read tools and reversible calls
  first.
- `companies.json` and the `.p8` keys under `Keys/` are local secrets (gitignored): never print,
  quote or commit them; `companies.example.json` is the shareable shape.
