import Foundation

/// モックデータ生成。`--demo` フラグで起動時にスクショ用のUIを表示する。
enum DemoDataProvider {

    /// 全 RequestType・リスクレベルを網羅するモックリクエスト
    static func mockRequests() -> [PermissionRequest] {
        let sessionId = "demo-session-abc12345"
        let cwd = FileManager.default.homeDirectoryForCurrentUser.path + "/projects/my-app"
        let now = Date()

        return [
            // High risk: rm コマンド
            PermissionRequest(
                id: UUID(),
                toolName: "Bash",
                toolInput: [
                    "command": "rm -rf node_modules && npm install",
                ] as [String: Any],
                toolUseId: "toolu_demo_001",
                sessionId: sessionId,
                cwd: cwd,
                tty: nil,
                receivedAt: now.addingTimeInterval(-5),
                permissionSuggestions: []
            ),

            // Low risk: Edit with diff
            PermissionRequest(
                id: UUID(),
                toolName: "Edit",
                toolInput: [
                    "file_path": cwd + "/src/components/App.tsx",
                    "old_string": "const App = () => {\n  return <div>Hello</div>\n}",
                    "new_string": "const App = () => {\n  const [count, setCount] = useState(0)\n  return (\n    <div>\n      <h1>Hello</h1>\n      <button onClick={() => setCount(c => c + 1)}>\n        Count: {count}\n      </button>\n    </div>\n  )\n}",
                ] as [String: Any],
                toolUseId: "toolu_demo_002",
                sessionId: sessionId,
                cwd: cwd,
                tty: nil,
                receivedAt: now.addingTimeInterval(-15),
                permissionSuggestions: [
                    ["type": "setMode", "mode": "acceptEdits", "destination": "session"] as [String: Any],
                ]
            ),

            // Medium risk: git commit
            PermissionRequest(
                id: UUID(),
                toolName: "Bash",
                toolInput: [
                    "command": "git commit -m \"feat: カウンターコンポーネントを追加\"",
                ] as [String: Any],
                toolUseId: "toolu_demo_003",
                sessionId: sessionId,
                cwd: cwd,
                tty: nil,
                receivedAt: now.addingTimeInterval(-30),
                permissionSuggestions: []
            ),

            // Question: AskUserQuestion
            PermissionRequest(
                id: UUID(),
                toolName: "AskUserQuestion",
                toolInput: [
                    "questions": [
                        [
                            "question": "Which testing framework would you like to use?",
                            "options": [
                                ["label": "Vitest (Recommended)", "description": "Fast, Vite-native test runner"],
                                ["label": "Jest", "description": "Mature ecosystem with wide adoption"],
                                ["label": "Playwright", "description": "E2E testing with browser automation"],
                            ] as [[String: Any]],
                        ] as [String: Any],
                    ] as [[String: Any]],
                ] as [String: Any],
                toolUseId: "toolu_demo_004",
                sessionId: sessionId,
                cwd: cwd,
                tty: nil,
                receivedAt: now.addingTimeInterval(-45),
                permissionSuggestions: []
            ),

            // Plan approval: ExitPlanMode
            PermissionRequest(
                id: UUID(),
                toolName: "ExitPlanMode",
                toolInput: [
                    "plan": """
                    ## Implementation Plan

                    1. Create `Counter` component with useState hook
                    2. Add unit tests with Vitest
                    3. Update App.tsx to include Counter
                    4. Run tests and verify coverage
                    """,
                    "allowedPrompts": [
                        ["tool": "Bash", "prompt": "Run vitest"] as [String: Any],
                        ["tool": "Edit", "prompt": "Edit source files"] as [String: Any],
                        ["tool": "Write", "prompt": "Create test files"] as [String: Any],
                    ] as [[String: Any]],
                ] as [String: Any],
                toolUseId: "toolu_demo_005",
                sessionId: sessionId,
                cwd: cwd,
                tty: nil,
                receivedAt: now.addingTimeInterval(-60),
                permissionSuggestions: []
            ),
        ]
    }

    /// 完了イベントのモック（成功 + エラー）
    static func mockCompletions() -> [CompletionInfo] {
        let sessionId = "demo-session-abc12345"
        let cwd = FileManager.default.homeDirectoryForCurrentUser.path + "/projects/my-app"

        return [
            CompletionInfo(
                toolName: "Bash",
                toolUseId: "toolu_demo_done_001",
                sessionId: sessionId,
                tty: nil,
                cwd: cwd,
                resultSummary: "Exit 0: src/  package.json  tsconfig.json  README.md",
                isError: false
            ),
            CompletionInfo(
                toolName: "Bash",
                toolUseId: "toolu_demo_done_002",
                sessionId: sessionId,
                tty: nil,
                cwd: cwd,
                resultSummary: "Exit 1: error TS2304: Cannot find name 'useState'",
                isError: true
            ),
        ]
    }
}
