# Contributing to asc-mcp

Thank you for your interest in contributing! This guide will help you get started.

## Getting Started

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/YOUR_USERNAME/asc-mcp.git`
3. **Create a branch**: `git checkout -b feature/your-feature`
4. **Build**: `swift build`
5. **Test**: `swift test`
6. **Commit** your changes: `git commit -m 'Add your feature'`
7. **Push**: `git push origin feature/your-feature`
8. **Open a Pull Request** against the `develop` branch

## Code Conventions

- **Swift 6** strict concurrency — all types must be `Sendable`, use proper actor isolation
- **Actors** for stateful services; avoid shared mutable state
- **async/await** for all I/O operations
- **No emojis** in commit messages or code comments
- Internal visibility by default; mark `public` only when necessary
- Comment all public methods with `///` doc comments

## Worker Structure

Each worker follows a 3-file pattern:

```
Workers/MyWorker/
├── MyWorker.swift                  # Main class, getTools(), handleTool()
├── MyWorker+ToolDefinitions.swift  # Tool schemas (name, description, parameters)
└── MyWorker+Handlers.swift         # Handler implementations
```

## Adding a New Tool to an Existing Worker

1. Add handler method in `Worker+Handlers.swift`
2. Add tool definition in `Worker+ToolDefinitions.swift`
3. Register in `getTools()` array
4. Add case to `handleTool()` switch
5. WorkerManager auto-routes by prefix — no changes needed there
6. Update tests in `WorkerToolDefinitionsTests.swift`

## Adding a New Worker

1. Create `Workers/MyWorker/` with 3 files (see structure above)
2. Create models in `Models/MyDomain/`
3. Register in `WorkerManager.swift`: property, init, `registerWorkers()`, `reinitializeWorkers()`, getter
4. Add worker name to `EntryPoint.swift` → `validWorkers` set
5. Add prefix description to `Application.swift` → server instructions
6. Update tests: `WorkerToolDefinitionsTests`, `WorkerRoutingTests`, `ParameterValidationTests`

## Testing Requirements

- All tests must pass: `swift test`
- Use Swift Testing framework (`@Suite`, `@Test`, `#expect`)
- Add tool count and name tests for any new/modified worker
- Add parameter validation tests for required parameters
- Use `TestFactory` helpers from `Tests/ASCMCPTests/Helpers/TestHelpers.swift`

## Pull Request Checklist

- [ ] `swift build` succeeds with no warnings
- [ ] `swift test` — all tests pass
- [ ] All new types are `Sendable`
- [ ] Public methods have `///` doc comments
- [ ] Worker tool counts updated in tests
- [ ] No hardcoded credentials or API keys

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).
