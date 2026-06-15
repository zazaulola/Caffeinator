APP_NAME    := Caffeinator
BUILD_DIR   := .build
RELEASE_DIR := $(BUILD_DIR)/release
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := /Applications

.PHONY: all build bundle run install uninstall clean

all: bundle

build:
	swift build -c release

bundle: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(RELEASE_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@codesign --force --sign - "$(APP_BUNDLE)" >/dev/null 2>&1 || true
	@echo "✓ Bundled at $(APP_BUNDLE)"

run: bundle
	open "$(APP_BUNDLE)"

install: bundle
	@if [ -d "$(INSTALL_DIR)/$(APP_NAME).app" ]; then \
		rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"; \
	fi
	cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo "✓ Installed to $(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	@launchctl bootout "gui/$$(id -u)/com.caffeinator.menubar" 2>/dev/null || true
	@rm -f "$$HOME/Library/LaunchAgents/com.caffeinator.menubar.plist"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "✓ Uninstalled"

clean:
	swift package clean
	rm -rf "$(BUILD_DIR)"
