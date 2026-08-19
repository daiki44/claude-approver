# Agent Approver

> **Disclaimer:** This is an unofficial, community-built tool. It is not affiliated with, endorsed by, or sponsored by Anthropic, PBC or OpenAI. "Claude" is a trademark of Anthropic, PBC.

A macOS menu bar app that presents permission and approval requests from terminal-based coding agents in a native SwiftUI popover.

<p align="center">
  <img src="docs/screenshots/questions-and-plans.png" width="360" alt="Approval requests in the menu bar popover" />
</p>

## Overview

```text
Agent harness  ──(local adapter)──>  Unix Domain Socket  ──>  SwiftUI menu bar app
       ▲                                                           │
       └────────────── allow / deny / passthrough ─────────────────┘
```

The app owns the native UI and request queue. Each supported harness has a small adapter that translates its local hook contract into the app's socket protocol.

Harness-specific setup and behavior live in separate documents:

- [Claude Code integration](docs/claude-code-integration.md)
- [Codex CLI integration](docs/codex-integration.md)

## Features

- Native menu bar popover for approval requests
- FIFO queue with concurrent request handling
- Allow, deny, deny with a reason, and passthrough actions
- Risk indicators based on tool input heuristics
- macOS notifications and keyboard shortcuts
- Automatic popover open/close and request cleanup
- Fail-open behavior when an adapter, socket, or app is unavailable

## Requirements

- macOS 14.0+
- Swift 5.9+ (Xcode 15+ or standalone Swift toolchain)
- Python 3 for the local adapters
- At least one supported harness; see the integration documents above

## Build and development

Build the Swift app:

```bash
cd ClaudeApprover
swift build -c release
```

Run the Python test suite:

```bash
python3 -m unittest discover -s tests -v
```

The repository also includes Makefile targets for bundling the app, installing the macOS LaunchAgent, running the demo mode, and cleaning build artifacts. Harness-specific installation commands are documented in the integration pages.

## Project structure

```text
ClaudeApprover/
  Package.swift                    # Swift Package Manager manifest
  Sources/                         # SwiftUI/AppKit menu bar app
    Models/                        # Requests, decisions, and queue state
    Services/                      # Unix Domain Socket and notifications
    ViewModels/                    # App coordination
    Views/                         # Popover and request cards

hook/
  *_permission_request.py          # Harness-specific request adapters
  socket_bridge.py                 # Length-prefixed UDS transport
  post_tool_use.py                 # Completion notification adapter

scripts/
  register_*_hook.py               # Harness hook registration
  unregister_*_hook.py             # Harness hook removal

docs/
  *-integration.md                 # Harness-specific setup and behavior
```

## App socket protocol

Adapters communicate with the app through:

```text
~/Library/Application Support/ClaudeApprover/claude-approver.sock
```

Messages use a 4-byte big-endian unsigned length header followed by a UTF-8 JSON body. The wire payload is intentionally an internal adapter protocol; each integration document explains how its harness fields map into it.

## Security and failure behavior

- The Unix socket directory is restricted to the current user.
- Adapters never persist approval data or credentials.
- A missing app, broken socket, malformed request, or adapter timeout returns control to the harness's native approval flow.
- Review the harness-specific hook trust and permission settings before enabling an integration.

## Logs

The app writes local runtime logs under `~/Library/Logs/ClaudeApprover/`. Adapter-specific debug log locations and commands are documented on each integration page.

Set `CLAUDE_APPROVER_DEBUG=1` to enable verbose adapter logging.

## License

MIT
