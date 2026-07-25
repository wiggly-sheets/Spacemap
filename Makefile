APP_NAME = spacemap
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app
APP_CONTENTS = $(APP_BUNDLE)/Contents
INSTALL_PATH = /Applications/$(APP_BUNDLE)
VERSION  := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || (cat VERSION 2>/dev/null) || echo "0.0.0")
ARCHIVE   = spacemap-$(VERSION).zip
STAGE     = spacemap-$(VERSION)
DMG       = spacemap-$(VERSION).dmg
DMG_STAGE = dmgstage
BUILD_ARM64 = .build/arm64-apple-macosx/release
BUILD_X86_64 = .build/x86_64-apple-macosx/release
# Sparkle public key for update verification (set via env or read from sparklesigner.pub)
SPARKLE_PUBLIC_KEY ?= $(shell cat sparklesigner.pub 2>/dev/null | tr -d '\n')

.PHONY: build app install run dev uninstall clean config distconfig archive dmg dmg-arm64 dmg-x86_64 dmg-universal permissions install-cli uninstall-cli build-arm64 build-x86_64 build-universal app-arm64 app-x86_64 app-universal generate-xcodeproj test

build:
	swift build -c release

test:
	swift test

generate-xcodeproj:
	python3 scripts/generate-xcodeproj.py

build-arm64:
	swift build -c release --arch arm64

build-x86_64:
	swift build -c release --arch x86_64

build-universal: build-arm64 build-x86_64
	mkdir -p .build/universal/release
	lipo -create -output .build/universal/release/$(APP_NAME) \
		$(BUILD_ARM64)/$(APP_NAME) \
		$(BUILD_X86_64)/$(APP_NAME)
	@echo "Universal binary: .build/universal/release/$(APP_NAME)"
	@lipo -info .build/universal/release/$(APP_NAME)

app: build
	mkdir -p $(APP_CONTENTS)/MacOS
	mkdir -p $(APP_CONTENTS)/Frameworks
	mkdir -p $(APP_CONTENTS)/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_CONTENTS)/MacOS/
	cp Sources/spacemap/Info.plist $(APP_CONTENTS)/
	sed -i '' "s/$$(grep -A1 CFBundleShortVersionString Sources/spacemap/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')/$(VERSION)/g" $(APP_CONTENTS)/Info.plist
	/usr/libexec/PlistBuddy -c "Add :SUAppcastURL string https://wiggly-sheets.github.io/spacemap/appcast.xml" $(APP_CONTENTS)/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(SPARKLE_PUBLIC_KEY)" $(APP_CONTENTS)/Info.plist 2>/dev/null || true
	# Copy Sparkle framework (extract from xcframework structure)
	cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(APP_CONTENTS)/Frameworks/
	# Add ../Frameworks to rpath so @rpath/Sparkle.framework resolves correctly at runtime
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP_CONTENTS)/MacOS/$(APP_NAME)
	cp Sources/spacemap/spacemap.icns $(APP_CONTENTS)/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(APP_CONTENTS)/Resources/AppIcon.icns
	cp -R Assets.xcassets $(APP_CONTENTS)/Resources/

app-arm64: build-arm64
	mkdir -p $(APP_NAME)-arm64.app/Contents/MacOS
	mkdir -p $(APP_NAME)-arm64.app/Contents/Frameworks
	mkdir -p $(APP_NAME)-arm64.app/Contents/Resources
	cp $(BUILD_ARM64)/$(APP_NAME) $(APP_NAME)-arm64.app/Contents/MacOS/
	cp Sources/spacemap/Info.plist $(APP_NAME)-arm64.app/Contents/
	CURRENT_VERSION=$$(grep -A1 CFBundleShortVersionString Sources/spacemap/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/') && sed -i '' "s/$$CURRENT_VERSION/$(VERSION)/g" $(APP_NAME)-arm64.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :SUAppcastURL string https://wiggly-sheets.github.io/spacemap/appcast.xml" $(APP_NAME)-arm64.app/Contents/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(SPARKLE_PUBLIC_KEY)" $(APP_NAME)-arm64.app/Contents/Info.plist 2>/dev/null || true
	# Copy Sparkle framework (extract from xcframework structure)
	cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(APP_NAME)-arm64.app/Contents/Frameworks/
	# Add ../Frameworks to rpath so @rpath/Sparkle.framework resolves correctly at runtime
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP_NAME)-arm64.app/Contents/MacOS/$(APP_NAME)
	cp Sources/spacemap/spacemap.icns $(APP_NAME)-arm64.app/Contents/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(APP_NAME)-arm64.app/Contents/Resources/AppIcon.icns
	cp -R Assets.xcassets $(APP_NAME)-arm64.app/Contents/Resources/
	@echo "Built $(APP_NAME)-arm64.app (Apple Silicon)"

app-x86_64: build-x86_64
	mkdir -p $(APP_NAME)-x86_64.app/Contents/MacOS
	mkdir -p $(APP_NAME)-x86_64.app/Contents/Frameworks
	mkdir -p $(APP_NAME)-x86_64.app/Contents/Resources
	cp $(BUILD_X86_64)/$(APP_NAME) $(APP_NAME)-x86_64.app/Contents/MacOS/
	cp Sources/spacemap/Info.plist $(APP_NAME)-x86_64.app/Contents/
	CURRENT_VERSION=$$(grep -A1 CFBundleShortVersionString Sources/spacemap/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/') && sed -i '' "s/$$CURRENT_VERSION/$(VERSION)/g" $(APP_NAME)-x86_64.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :SUAppcastURL string https://wiggly-sheets.github.io/spacemap/appcast.xml" $(APP_NAME)-x86_64.app/Contents/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(SPARKLE_PUBLIC_KEY)" $(APP_NAME)-x86_64.app/Contents/Info.plist 2>/dev/null || true
	# Copy Sparkle framework (extract from xcframework structure)
	cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(APP_NAME)-x86_64.app/Contents/Frameworks/
	# Add ../Frameworks to rpath so @rpath/Sparkle.framework resolves correctly at runtime
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP_NAME)-x86_64.app/Contents/MacOS/$(APP_NAME)
	cp Sources/spacemap/spacemap.icns $(APP_NAME)-x86_64.app/Contents/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(APP_NAME)-x86_64.app/Contents/Resources/AppIcon.icns
	cp -R Assets.xcassets $(APP_NAME)-x86_64.app/Contents/Resources/
	@echo "Built $(APP_NAME)-x86_64.app (Intel)"

app-universal: build-universal
	mkdir -p $(APP_NAME).app/Contents/MacOS
	mkdir -p $(APP_NAME).app/Contents/Frameworks
	mkdir -p $(APP_NAME).app/Contents/Resources
	cp .build/universal/release/$(APP_NAME) $(APP_NAME).app/Contents/MacOS/
	cp Sources/spacemap/Info.plist $(APP_NAME).app/Contents/
	CURRENT_VERSION=$$(grep -A1 CFBundleShortVersionString Sources/spacemap/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/') && sed -i '' "s/$$CURRENT_VERSION/$(VERSION)/g" $(APP_NAME).app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Add :SUAppcastURL string https://wiggly-sheets.github.io/spacemap/appcast.xml" $(APP_NAME).app/Contents/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(SPARKLE_PUBLIC_KEY)" $(APP_NAME).app/Contents/Info.plist 2>/dev/null || true
	# Copy Sparkle framework (extract from xcframework structure)
	cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(APP_NAME).app/Contents/Frameworks/
	# Add ../Frameworks to rpath so @rpath/Sparkle.framework resolves correctly at runtime
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP_NAME).app/Contents/MacOS/$(APP_NAME)
	cp Sources/spacemap/spacemap.icns $(APP_NAME).app/Contents/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(APP_NAME).app/Contents/Resources/AppIcon.icns
	cp -R Assets.xcassets $(APP_NAME).app/Contents/Resources/
	@echo "Built $(APP_NAME).app (Universal: arm64 + x86_64)"

archive: app
	rm -rf $(STAGE) $(ARCHIVE)
	mkdir -p $(STAGE)
	cp -R $(APP_BUNDLE) $(STAGE)/
	codesign --force --deep --sign - $(STAGE)/$(APP_BUNDLE)
	zip -r --symlinks $(ARCHIVE) $(STAGE)
	rm -rf $(STAGE)
	@echo ""
	@echo "Artifact: $(ARCHIVE)"
	@echo "SHA-256:  $$(shasum -a 256 $(ARCHIVE) | awk '{print $$1}')"
	@echo ""
	@echo "Next: go to https://github.com/jsheffie/spacemap/releases/new"
	@echo "  1. Tag: v$(VERSION)"
	@echo "  2. Click 'Generate release notes'"
	@echo "  3. Attach $(ARCHIVE)"
	@echo "  4. Copy the SHA-256 above into Formula/spacemap.rb in homebrew-tap"

dmg: app
	@$(MAKE) _dmg INPUT=$(APP_BUNDLE) OUTPUT=$(DMG)

dmg-arm64: app-arm64
	@$(MAKE) _dmg INPUT=$(APP_NAME)-arm64.app OUTPUT=$(APP_NAME)-$(VERSION)-arm64.dmg

dmg-x86_64: app-x86_64
	@$(MAKE) _dmg INPUT=$(APP_NAME)-x86_64.app OUTPUT=$(APP_NAME)-$(VERSION)-x86_64.dmg

dmg-universal: app-universal
	@$(MAKE) _dmg INPUT=$(APP_NAME).app OUTPUT=$(APP_NAME)-$(VERSION)-universal.dmg

_dmg:
	@rm -rf $(DMG_STAGE)
	@mkdir -p $(DMG_STAGE)
	@cp -R $(INPUT) $(DMG_STAGE)/$(APP_NAME).app
	create-dmg --no-internet-enable \
		--volname "$(APP_NAME)" \
		--volicon Sources/spacemap/spacemap.icns \
		--window-pos 200 120 \
		--window-size 600 400 \
		--icon-size 100 \
		--icon "$(APP_NAME).app" 175 190 \
		--app-drop-link 425 190 \
		$(OUTPUT) $(DMG_STAGE)/$(APP_NAME).app
	@rm -rf $(DMG_STAGE)
	@echo "Created $(OUTPUT)"
	@echo "SHA-256:  $$(shasum -a 256 $(OUTPUT) | awk '{print $$1}')"

install: app
	mkdir -p $(INSTALL_PATH)/Contents/MacOS
	mkdir -p $(INSTALL_PATH)/Contents/Frameworks
	mkdir -p $(INSTALL_PATH)/Contents/Resources
	cp $(APP_CONTENTS)/MacOS/$(APP_NAME) $(INSTALL_PATH)/Contents/MacOS/
	cp $(APP_CONTENTS)/Info.plist $(INSTALL_PATH)/Contents/
	cp -R $(APP_CONTENTS)/Frameworks/Sparkle.framework $(INSTALL_PATH)/Contents/Frameworks/
	cp Sources/spacemap/spacemap.icns $(INSTALL_PATH)/Contents/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(INSTALL_PATH)/Contents/Resources/AppIcon.icns
	cp -R Assets.xcassets $(INSTALL_PATH)/Contents/Resources/
	@echo "Installed to $(INSTALL_PATH)"

run: install
	@# Always launch via 'open', never run the binary directly
	open $(INSTALL_PATH)

uninstall:
	-killall $(APP_NAME) 2>/dev/null
	rm -rf $(INSTALL_PATH)
	@echo "Removed $(INSTALL_PATH)"

install-cli: install
	@echo "Installing CLI symlink to /usr/local/bin/spacemap..."
	@mkdir -p /usr/local/bin
	@ln -sf $(INSTALL_PATH)/Contents/MacOS/$(APP_NAME) /usr/local/bin/spacemap
	@echo "CLI installed. Run 'spacemap --help' for usage."

uninstall-cli:
	@echo "Removing CLI symlink from /usr/local/bin/spacemap..."
	@rm -f /usr/local/bin/spacemap
	@echo "CLI uninstalled."

dev1: uninstall
	@echo ""
	@echo "IMPORTANT: macOS will revok Accessibility permission because the binary will change."
	@echo "Go to System Settings → Privacy & Security → Accessibility"
	@echo "Remove spacemap (− button), you will be prompted to re-add it when we re-install it."

dev2: install
	@# This target kills the app, reinstalls, and relaunches so you just need to re-grant in System Settings.
	-killall $(APP_NAME) 2>/dev/null
	@sleep 0.5
	open $(INSTALL_PATH)
	@echo ""
	@echo "IMPORTANT: you have to give macOS Accessibility permission because the binary changed."
	@echo "Go to System Settings → Privacy & Security → Accessibility"
	@echo "and grant it permissions the prompt that appears."

permissions:
	@echo "If your hotkey stopped working after a reinstall:"
	@echo "  1. killall spacemap"
	@echo "  2. System Settings → Privacy & Security → Accessibility"
	@echo "  3. Click − to remove spacemap"
	@echo "  4. make run   (will prompt for permission again)"
	@echo ""
	@echo "NEVER run the binary directly — always use 'make run' or 'open $(INSTALL_PATH)'"
	@echo "Running the binary directly causes AXIsProcessTrusted() to return false."

clean:
	rm -rf .build $(APP_BUNDLE)

config:
	mkdir -p ~/.config/spacemap
	@if [ ! -f ~/.config/spacemap/config ]; then \
		echo "GRID_COLS=8" > ~/.config/spacemap/config; \
		echo "GRID_ROWS=2" >> ~/.config/spacemap/config; \
		echo "#CELL_STYLE=rects" >> ~/.config/spacemap/config; \
		echo "CELL_STYLE=icons" >> ~/.config/spacemap/config; \
		echo "#CELL_STYLE=hybrid" >> ~/.config/spacemap/config; \
		echo "#HOTKEY=ctrl+pgdn" >> ~/.config/spacemap/config; \
		echo "#UI_SCALE=1.0" >> ~/.config/spacemap/config; \
		echo "#AUTO_SHOW=false" >> ~/.config/spacemap/config; \
		echo "#AUTO_HIDE_TIMEOUT=5" >> ~/.config/spacemap/config; \
		echo "#THEME=default" >> ~/.config/spacemap/config; \
		echo "#SOCKET_HEALTH_INTERVAL=60" >> ~/.config/spacemap/config; \
		echo "SPACE_NAMES=1:Desktop,2:Dev" >> ~/.config/spacemap/config; \
		echo "Created ~/.config/spacemap/config with defaults (8x2, icons)"; \
	else \
		echo "Config already exists at ~/.config/spacemap/config"; \
		cat ~/.config/spacemap/config; \
	fi

distconfig:
	mkdir -p ~/.config/spacemap
	@echo "GRID_COLS=8" > ~/.config/spacemap/config
	@echo "GRID_ROWS=2" >> ~/.config/spacemap/config
	@echo "#CELL_STYLE=rects" >> ~/.config/spacemap/config
	@echo "CELL_STYLE=icons" >> ~/.config/spacemap/config
	@echo "#CELL_STYLE=hybrid" >> ~/.config/spacemap/config
	@echo "#HOTKEY=ctrl+pgdn" >> ~/.config/spacemap/config
	@echo "#SOCKET_HEALTH_INTERVAL=60" >> ~/.config/spacemap/config
	@echo "SPACE_NAMES=1:Desktop,2:Dev" >> ~/.config/spacemap/config
	@echo "Wrote ~/.config/spacemap/config"
	@cat ~/.config/spacemap/config

symlink:
	ln -sf /Applications/spacemap.app/Contents/MacOS/spacemap /usr/local/bin/spacemap
	@echo "Symlink created: /usr/local/bin/spacemap → /Applications/spacemap.app/Contents/MacOS/spacemap"
	@echo "Note: You may need to run with sudo for /usr/local/bin access"

unsymlink:
	rm -f /usr/local/bin/spacemap
	@echo "Symlink removed"
