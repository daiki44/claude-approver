.PHONY: build bundle install uninstall clean start stop restart

PREFIX := $(HOME)/.claude/claude-approver
BUILD_DIR := $(PREFIX)/ClaudeApprover
BINARY := $(BUILD_DIR)/.build/release/ClaudeApprover
APP_BUNDLE := $(PREFIX)/ClaudeApprover.app
APP_BINARY := $(APP_BUNDLE)/Contents/MacOS/ClaudeApprover
INFO_PLIST_SRC := $(PREFIX)/scripts/Info.plist
PLIST_SRC := $(PREFIX)/scripts/com.claude.approver.plist
PLIST_DST := $(HOME)/Library/LaunchAgents/com.claude.approver.plist
LOG_DIR := $(HOME)/Library/Logs/ClaudeApprover

# ──────────────────────────────────────────────
# Build
# ──────────────────────────────────────────────

build:
	@echo "Building ClaudeApprover (release)..."
	cd $(BUILD_DIR) && swift build -c release
	@echo "Build complete: $(BINARY)"

# ──────────────────────────────────────────────
# Bundle (.app)
# ──────────────────────────────────────────────

bundle: build
	@echo "Creating .app bundle..."
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp $(BINARY) "$(APP_BINARY)"
	@cp $(INFO_PLIST_SRC) "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --sign - "$(APP_BUNDLE)"
	@echo "Bundle created: $(APP_BUNDLE)"

# ──────────────────────────────────────────────
# Install
# ──────────────────────────────────────────────

install: bundle
	@echo "Registering hook in settings.json..."
	python3 $(PREFIX)/scripts/register_hook.py
	@echo ""
	@echo "Installing LaunchAgent..."
	@mkdir -p $(LOG_DIR)
	@cp $(PLIST_SRC) $(PLIST_DST)
	launchctl load $(PLIST_DST)
	@echo ""
	@echo "Installation complete!"
	@echo "  - Hook registered (restart Claude Code to activate)"
	@echo "  - App launched via LaunchAgent"
	@echo ""
	@echo "To verify: look for the shield icon in the menu bar."

# ──────────────────────────────────────────────
# Uninstall
# ──────────────────────────────────────────────

uninstall:
	@echo "Stopping LaunchAgent..."
	-launchctl unload $(PLIST_DST) 2>/dev/null
	-rm -f $(PLIST_DST)
	@echo "Unregistering hook..."
	python3 $(PREFIX)/scripts/unregister_hook.py
	@echo ""
	@echo "Uninstall complete. Restart Claude Code for changes to take effect."

# ──────────────────────────────────────────────
# Lifecycle
# ──────────────────────────────────────────────

start:
	launchctl load $(PLIST_DST)

stop:
	-launchctl unload $(PLIST_DST) 2>/dev/null

restart: stop start

# ──────────────────────────────────────────────
# Clean
# ──────────────────────────────────────────────

clean:
	cd $(BUILD_DIR) && swift package clean
	rm -rf "$(APP_BUNDLE)"
	@echo "Clean complete."
