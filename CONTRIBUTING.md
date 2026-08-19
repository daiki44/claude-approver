# Contributing

Thank you for your interest in contributing to ClaudeApprover!

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/daiki44/agent-approver.git ~/.claude/claude-approver
   cd ~/.claude/claude-approver
   ```

2. Build:
   ```bash
   make build
   ```

3. Run locally:
   ```bash
   make bundle && make install
   ```

## Requirements

- macOS 14.0+
- Swift 5.9+ (Xcode 15+)
- Python 3

## Project Structure

- **Swift app** (`ClaudeApprover/Sources/`): Menu bar app with MVVM architecture
- **Python hooks** (`hook/`): Bridge between Claude Code and the Swift app
- **Scripts** (`scripts/`): Installation and hook registration

## Guidelines

- No external dependencies (Swift: Apple frameworks only; Python: standard library only)
- Follow existing code style and naming conventions
- Use SPM for Swift compilation (no Xcode project)
- Hooks must follow the fail-open principle (errors → exit 1 → passthrough)

## Submitting Changes

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Ensure `make build` succeeds
5. Submit a pull request

## Reporting Issues

Please open an issue on GitHub with:
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Relevant log output (`~/.claude/approver_debug.log`)
