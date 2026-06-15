APP_NAME    := Caffeinator
ARCHS       := --arch arm64 --arch x86_64
BUILD_DIR   := .build
# Universal (--arch ...) builds land under apple/Products, not release/.
RELEASE_DIR := $(BUILD_DIR)/apple/Products/Release
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := /Applications

.PHONY: all build bundle run install uninstall clean icon

all: bundle

build:
	swift build -c release $(ARCHS)

bundle: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(RELEASE_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@codesign --force --sign - "$(APP_BUNDLE)" >/dev/null 2>&1 || true
	@echo "✓ Bundled at $(APP_BUNDLE) ($$(lipo -archs "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"))"

# Regenerate Resources/AppIcon.icns from scripts/generate-icon.swift
icon:
	@rm -rf "$(BUILD_DIR)/iconset" "$(BUILD_DIR)/AppIcon.iconset"
	@swift scripts/generate-icon.swift "$(BUILD_DIR)/iconset"
	@mkdir -p "$(BUILD_DIR)/AppIcon.iconset"
	@cp "$(BUILD_DIR)/iconset"/icon_*.png "$(BUILD_DIR)/AppIcon.iconset/"
	@iconutil -c icns "$(BUILD_DIR)/AppIcon.iconset" -o Resources/AppIcon.icns
	@echo "✓ Wrote Resources/AppIcon.icns"

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
