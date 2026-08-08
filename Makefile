APP_NAME = spacemap
BINARY_NAME = Spacemap
BUILD_DIR = .build/release
APP_BUNDLE = Spacemap.app
APP_CONTENTS = $(APP_BUNDLE)/Contents
INSTALL_PATH = /Applications/$(APP_BUNDLE)
VERSION  := $(shell cat VERSION 2>/dev/null || git tag --sort=-v:refname 2>/dev/null | head -1 | sed 's/^v//' || grep -A1 CFBundleShortVersionString Sources/spacemap/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/' || echo "0.0.0")
ARCHIVE   = spacemap-$(VERSION).zip
STAGE     = spacemap-$(VERSION)
DMG       = spacemap-$(VERSION).dmg
DMG_STAGE = dmgstage
BUILD_ARM64 = .build/arm64-apple-macosx/release
BUILD_X86_64 = .build/x86_64-apple-macosx/release
# Sparkle public key for update verification (set via env or read from sparklesigner.pub)
SPARKLE_PUBLIC_KEY ?= $(shell cat sparklesigner.pub 2>/dev/null | tr -d '\n')
MAN_SOURCE = docs/spacemap.1.scd
MAN_PAGE = docs/spacemap.1

.PHONY: build app install run dev uninstall clean config distconfig archive dmg dmg-arm64 dmg-x86_64 dmg-universal permissions install-cli uninstall-cli build-arm64 build-x86_64 build-universal app-arm64 app-x86_64 app-universal generate-xcodeproj test release man

build:
	swift build -c release --product $(BINARY_NAME)

test:
	swift test

man: $(MAN_PAGE)

$(MAN_PAGE): $(MAN_SOURCE)
	@command -v scdoc >/dev/null || (echo "scdoc is required to build $(MAN_PAGE)" && exit 1)
	scdoc < $(MAN_SOURCE) > $(MAN_PAGE)

generate-xcodeproj:
	python3 scripts/generate-xcodeproj.py

build-arm64:
	swift build -c release --arch arm64 --product $(BINARY_NAME)

build-x86_64:
	swift build -c release --arch x86_64 --product $(BINARY_NAME)

build-universal: build-arm64 build-x86_64
	mkdir -p .build/universal/release
	lipo -create -output .build/universal/release/$(BINARY_NAME) \
		$(BUILD_ARM64)/$(BINARY_NAME) \
		$(BUILD_X86_64)/$(BINARY_NAME)
	@echo "Universal binary: .build/universal/release/$(BINARY_NAME)"
	@lipo -info .build/universal/release/$(BINARY_NAME)

app: build man
	mkdir -p $(APP_CONTENTS)/MacOS
	mkdir -p $(APP_CONTENTS)/Frameworks
	mkdir -p $(APP_CONTENTS)/Resources
	rm -f $(APP_CONTENTS)/MacOS/$(APP_NAME)
	cp $(BUILD_DIR)/$(BINARY_NAME) $(APP_CONTENTS)/MacOS/
	cp Sources/spacemap/Info.plist $(APP_CONTENTS)/
	sed -i '' "s/$$(grep -A1 CFBundleShortVersionString Sources/spacemap/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')/$(VERSION)/g" $(APP_CONTENTS)/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP_CONTENTS)/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://wiggly-sheets.github.io/Spacemap/appcast.xml" $(APP_CONTENTS)/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://wiggly-sheets.github.io/Spacemap/appcast.xml" $(APP_CONTENTS)/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(SPARKLE_PUBLIC_KEY)" $(APP_CONTENTS)/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $(SPARKLE_PUBLIC_KEY)" $(APP_CONTENTS)/Info.plist 2>/dev/null || true
	# Copy Sparkle framework (extract from xcframework structure)
	cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(APP_CONTENTS)/Frameworks/
	# Add ../Frameworks to rpath so @rpath/Sparkle.framework resolves correctly at runtime
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP_CONTENTS)/MacOS/$(BINARY_NAME)
	cp Sources/spacemap/spacemap.icns $(APP_CONTENTS)/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(APP_CONTENTS)/Resources/AppIcon.icns
	cp Assets/AppIcon/Assets.car $(APP_CONTENTS)/Resources/Assets.car
	cp -R Assets.xcassets $(APP_CONTENTS)/Resources/
	cp $(MAN_PAGE) $(APP_CONTENTS)/Resources/spacemap.1

app-arm64: build-arm64 man
	mkdir -p $(APP_NAME)-arm64.app/Contents/MacOS
	mkdir -p $(APP_NAME)-arm64.app/Contents/Frameworks
	mkdir -p $(APP_NAME)-arm64.app/Contents/Resources
	rm -f $(APP_NAME)-arm64.app/Contents/MacOS/$(APP_NAME)
	cp $(BUILD_ARM64)/$(BINARY_NAME) $(APP_NAME)-arm64.app/Contents/MacOS/
	cp Sources/spacemap/Info.plist $(APP_NAME)-arm64.app/Contents/
	CURRENT_VERSION=$$(grep -A1 CFBundleShortVersionString Sources/spacemap/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/') && sed -i '' "s/$$CURRENT_VERSION/$(VERSION)/g" $(APP_NAME)-arm64.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP_NAME)-arm64.app/Contents/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://wiggly-sheets.github.io/Spacemap/appcast.xml" $(APP_NAME)-arm64.app/Contents/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://wiggly-sheets.github.io/Spacemap/appcast.xml" $(APP_NAME)-arm64.app/Contents/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(SPARKLE_PUBLIC_KEY)" $(APP_NAME)-arm64.app/Contents/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $(SPARKLE_PUBLIC_KEY)" $(APP_NAME)-arm64.app/Contents/Info.plist 2>/dev/null || true
	# Copy Sparkle framework (extract from xcframework structure)
	cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(APP_NAME)-arm64.app/Contents/Frameworks/
	# Add ../Frameworks to rpath so @rpath/Sparkle.framework resolves correctly at runtime
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP_NAME)-arm64.app/Contents/MacOS/$(BINARY_NAME)
	cp Sources/spacemap/spacemap.icns $(APP_NAME)-arm64.app/Contents/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(APP_NAME)-arm64.app/Contents/Resources/AppIcon.icns
	cp Assets/AppIcon/Assets.car $(APP_NAME)-arm64.app/Contents/Resources/Assets.car
	cp -R Assets.xcassets $(APP_NAME)-arm64.app/Contents/Resources/
	cp $(MAN_PAGE) $(APP_NAME)-arm64.app/Contents/Resources/spacemap.1
	@echo "Built $(APP_NAME)-arm64.app (Apple Silicon)"

app-x86_64: build-x86_64 man
	mkdir -p $(APP_NAME)-x86_64.app/Contents/MacOS
	mkdir -p $(APP_NAME)-x86_64.app/Contents/Frameworks
	mkdir -p $(APP_NAME)-x86_64.app/Contents/Resources
	rm -f $(APP_NAME)-x86_64.app/Contents/MacOS/$(APP_NAME)
	cp $(BUILD_X86_64)/$(BINARY_NAME) $(APP_NAME)-x86_64.app/Contents/MacOS/
	cp Sources/spacemap/Info.plist $(APP_NAME)-x86_64.app/Contents/
	CURRENT_VERSION=$$(grep -A1 CFBundleShortVersionString Sources/spacemap/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/') && sed -i '' "s/$$CURRENT_VERSION/$(VERSION)/g" $(APP_NAME)-x86_64.app/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP_NAME)-x86_64.app/Contents/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://wiggly-sheets.github.io/Spacemap/appcast.xml" $(APP_NAME)-x86_64.app/Contents/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://wiggly-sheets.github.io/Spacemap/appcast.xml" $(APP_NAME)-x86_64.app/Contents/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(SPARKLE_PUBLIC_KEY)" $(APP_NAME)-x86_64.app/Contents/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $(SPARKLE_PUBLIC_KEY)" $(APP_NAME)-x86_64.app/Contents/Info.plist 2>/dev/null || true
	# Copy Sparkle framework (extract from xcframework structure)
	cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(APP_NAME)-x86_64.app/Contents/Frameworks/
	# Add ../Frameworks to rpath so @rpath/Sparkle.framework resolves correctly at runtime
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP_NAME)-x86_64.app/Contents/MacOS/$(BINARY_NAME)
	cp Sources/spacemap/spacemap.icns $(APP_NAME)-x86_64.app/Contents/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(APP_NAME)-x86_64.app/Contents/Resources/AppIcon.icns
	cp Assets/AppIcon/Assets.car $(APP_NAME)-x86_64.app/Contents/Resources/Assets.car
	cp -R Assets.xcassets $(APP_NAME)-x86_64.app/Contents/Resources/
	cp $(MAN_PAGE) $(APP_NAME)-x86_64.app/Contents/Resources/spacemap.1
	@echo "Built $(APP_NAME)-x86_64.app (Intel)"

app-universal: build-universal man
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Frameworks
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	rm -f $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp .build/universal/release/$(BINARY_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Sources/spacemap/Info.plist $(APP_BUNDLE)/Contents/
	CURRENT_VERSION=$$(grep -A1 CFBundleShortVersionString Sources/spacemap/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/') && sed -i '' "s/$$CURRENT_VERSION/$(VERSION)/g" $(APP_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://wiggly-sheets.github.io/Spacemap/appcast.xml" $(APP_BUNDLE)/Contents/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://wiggly-sheets.github.io/Spacemap/appcast.xml" $(APP_BUNDLE)/Contents/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(SPARKLE_PUBLIC_KEY)" $(APP_BUNDLE)/Contents/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $(SPARKLE_PUBLIC_KEY)" $(APP_BUNDLE)/Contents/Info.plist 2>/dev/null || true
	# Copy Sparkle framework (extract from xcframework structure)
	cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(APP_BUNDLE)/Contents/Frameworks/
	# Add ../Frameworks to rpath so @rpath/Sparkle.framework resolves correctly at runtime
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(APP_BUNDLE)/Contents/MacOS/$(BINARY_NAME)
	cp Sources/spacemap/spacemap.icns $(APP_BUNDLE)/Contents/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	cp Assets/AppIcon/Assets.car $(APP_BUNDLE)/Contents/Resources/Assets.car
	cp -R Assets.xcassets $(APP_BUNDLE)/Contents/Resources/
	cp $(MAN_PAGE) $(APP_BUNDLE)/Contents/Resources/spacemap.1
	@echo "Built $(APP_BUNDLE) (Universal: arm64 + x86_64)"

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
	@cp -R $(INPUT) $(DMG_STAGE)/Spacemap.app
	create-dmg --no-internet-enable \
		--volname "Spacemap" \
		--volicon Sources/spacemap/spacemap.icns \
		--window-pos 200 120 \
		--window-size 660 400 \
		--background Assets/DMG/background.png \
		--icon-size 100 \
		--icon "Spacemap.app" 180 215 \
		--app-drop-link 480 215 \
		$(OUTPUT) $(DMG_STAGE)/Spacemap.app
	@rm -rf $(DMG_STAGE)
	@echo "Created $(OUTPUT)"
	@echo "SHA-256:  $$(shasum -a 256 $(OUTPUT) | awk '{print $$1}')"

install: app
	mkdir -p $(INSTALL_PATH)/Contents/MacOS
	mkdir -p $(INSTALL_PATH)/Contents/Frameworks
	mkdir -p $(INSTALL_PATH)/Contents/Resources
	rm -f $(INSTALL_PATH)/Contents/MacOS/$(APP_NAME)
	cp $(APP_CONTENTS)/MacOS/$(BINARY_NAME) $(INSTALL_PATH)/Contents/MacOS/
	cp $(APP_CONTENTS)/Info.plist $(INSTALL_PATH)/Contents/
	cp -R $(APP_CONTENTS)/Frameworks/Sparkle.framework $(INSTALL_PATH)/Contents/Frameworks/
	cp Sources/spacemap/spacemap.icns $(INSTALL_PATH)/Contents/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(INSTALL_PATH)/Contents/Resources/AppIcon.icns
	cp Assets/AppIcon/Assets.car $(INSTALL_PATH)/Contents/Resources/Assets.car
	cp -R Assets.xcassets $(INSTALL_PATH)/Contents/Resources/
	cp $(MAN_PAGE) $(INSTALL_PATH)/Contents/Resources/spacemap.1
	# Sign with Sparkle entitlements (ad-hoc for dev builds)
	codesign --force --sign - --options runtime \
		--entitlements sparkle-entitlements.plist \
		$(INSTALL_PATH)/Contents/MacOS/$(BINARY_NAME)
	codesign --force --sign - --options runtime \
		--entitlements sparkle-entitlements.plist \
		$(INSTALL_PATH)
	@echo "Installed to $(INSTALL_PATH)"

run: install
	@# Always launch via 'open', never run the binary directly
	open $(INSTALL_PATH)

uninstall:
	-killall $(BINARY_NAME) 2>/dev/null
	rm -rf $(INSTALL_PATH)
	@echo "Removed $(INSTALL_PATH)"
	@rm -f /usr/local/bin/spacemap

install-cli: install
	@echo "Installing CLI symlink to /usr/local/bin/spacemap..."
	@mkdir -p /usr/local/bin
	@ln -sf $(INSTALL_PATH)/Contents/MacOS/$(BINARY_NAME) /usr/local/bin/spacemap
	@mkdir -p /usr/local/share/man/man1
	@ln -sf $(INSTALL_PATH)/Contents/Resources/spacemap.1 /usr/local/share/man/man1/spacemap.1
	@echo "CLI and man page installed. Run 'man spacemap' for usage."

uninstall-cli:
	@echo "Removing CLI symlink from /usr/local/bin/spacemap..."
	@rm -f /usr/local/bin/spacemap
	@rm -f /usr/local/share/man/man1/spacemap.1
	@echo "CLI uninstalled."

dev1: uninstall
	@echo ""
	@echo "IMPORTANT: macOS will revoke Accessibility permission because the binary will change."
	@echo "Go to System Settings → Privacy & Security → Accessibility"
	@echo "Remove Spacemap (− button), you will be prompted to re-add it when we re-install it."

dev2: install
	@# This target kills the app, reinstalls, and relaunches so you just need to re-grant in System Settings.
	-killall $(BINARY_NAME) 2>/dev/null
	@sleep 0.5
	open $(INSTALL_PATH)
	@echo ""
	@echo "IMPORTANT: you have to give macOS Accessibility permission because the binary changed."
	@echo "Go to System Settings → Privacy & Security → Accessibility"
	@echo "and grant it permissions the prompt that appears."

permissions:
	@echo "If your hotkey stopped working after a reinstall:"
	@echo "  1. killall $(BINARY_NAME)"
	@echo "  2. System Settings → Privacy & Security → Accessibility"
	@echo "  3. Click − to remove Spacemap"
	@echo "  4. make run   (will prompt for permission again)"
	@echo ""
	@echo "NEVER run the binary directly — always use 'make run' or 'open $(INSTALL_PATH)'"
	@echo "Running the binary directly causes AXIsProcessTrusted() to return false."

release:
	@test -n "$(RELEASE)" || (echo "Usage: make release RELEASE=x.y.z" && exit 1)
	@# Auto-generate changelog entry from git diff
	@chmod +x scripts/generate-changelog.sh
	@scripts/generate-changelog.sh "$(RELEASE)"
	@grep -q "$(RELEASE)" CHANGELOG.md || (echo "ERROR: CHANGELOG.md has no entry for $(RELEASE). Update it manually." && exit 1)
	@echo "Releasing v$(RELEASE)..."
	@# Update Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(RELEASE)" Sources/spacemap/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(RELEASE)" Sources/spacemap/Info.plist
	@# Update VERSION file
	@echo "$(RELEASE)" > VERSION
	@# Commit, tag, push
	git add Sources/spacemap/Info.plist VERSION CHANGELOG.md
	git commit -m "v$(RELEASE)"
	git tag "v$(RELEASE)"
	git push origin main --tags
	@echo ""
	@echo "Tagged v$(RELEASE) — GitHub Actions will build & release."
	@echo "https://github.com/wiggly-sheets/Spacemap/releases"

clean:
	rm -rf .build $(APP_BUNDLE)

config:
	mkdir -p ~/.config/spacemap
	@if [ ! -f ~/.config/spacemap/config.toml ]; then \
		printf '%s\n' \
			'# Spacemap config; missing fields are filled automatically.' \
			'[grid]' \
			'cols = 8' \
			'rows = 2' \
			'cellStyle = "icons"' \
			'maxSpaces = 16' \
			'' \
			'[appearance]' \
			'theme = "default"' \
			'' \
			'[spaceNames.names]' \
			'"1" = "Desktop"' \
			'"2" = "Dev"' > ~/.config/spacemap/config.toml; \
		echo "Created ~/.config/spacemap/config.toml"; \
	else \
		echo "Config already exists at ~/.config/spacemap/config.toml"; \
		cat ~/.config/spacemap/config.toml; \
	fi

distconfig:
	mkdir -p ~/.config/spacemap
	@printf '%s\n' \
		'# Spacemap config; missing fields are filled automatically.' \
		'[grid]' \
		'cols = 8' \
		'rows = 2' \
		'cellStyle = "icons"' \
		'maxSpaces = 16' \
		'' \
		'[appearance]' \
		'theme = "default"' \
		'' \
		'[spaceNames.names]' > ~/.config/spacemap/config.toml
	@echo "Wrote ~/.config/spacemap/config.toml"
	@cat ~/.config/spacemap/config.toml

symlink:
	ln -sf /Applications/Spacemap.app/Contents/MacOS/$(BINARY_NAME) /usr/local/bin/spacemap
	@echo "Symlink created: /usr/local/bin/spacemap → /Applications/Spacemap.app/Contents/MacOS/$(BINARY_NAME)"
	@echo "Note: You may need to run with sudo for /usr/local/bin access"

unsymlink:
	rm -f /usr/local/bin/spacemap
	@echo "Symlink removed"
