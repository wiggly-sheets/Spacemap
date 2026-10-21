# Spacemap — build interface.
#
# `make` prints the list of targets. Every target is phony.

APP_NAME = spacemap
BINARY_NAME = Spacemap
APP_BUNDLE = Spacemap.app
APP_CONTENTS = $(APP_BUNDLE)/Contents
INSTALL_PATH = /Applications/$(APP_BUNDLE)
VERSION  := $(shell cat VERSION 2>/dev/null || git tag --sort=-v:refname 2>/dev/null | head -1 | sed 's/^v//' || grep -A1 CFBundleShortVersionString Sources/spacemap/Info.plist | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/' || echo "0.0.0")
ARCHIVE   = spacemap-$(VERSION).zip
STAGE     = spacemap-$(VERSION)
DMG_STAGE = dmgstage
BUILD_ARM64 = .build/arm64-apple-macosx/release
BUILD_X86_64 = .build/x86_64-apple-macosx/release
# The disk images. The Homebrew tap downloads the arm64 and the x86_64
# image; the universal image feeds the Sparkle appcast.
DMG_ARM   = $(APP_NAME)-$(VERSION)-arm64.dmg
DMG_INTEL = $(APP_NAME)-$(VERSION)-x86_64.dmg
DMG_UNIV  = $(APP_NAME)-$(VERSION)-universal.dmg
# Sparkle public key for update verification (set via env or read from sparklesigner.pub)
SPARKLE_PUBLIC_KEY ?= $(shell cat sparklesigner.pub 2>/dev/null | tr -d '\n')
# Release builds must embed SUPublicEDKey; dev/CI builds warn and skip it.
# Release entry points (archive, dmg*, release workflow) set REQUIRE_SPARKLE_KEY=1.
REQUIRE_SPARKLE_KEY ?= 0
# Deferred (=, not :=): the xcframework slice triplet changes with the toolchain,
# and the directory only exists after the build prerequisite fetches artifacts.
SPARKLE_FRAMEWORK = $(firstword $(wildcard .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework))
MAN_SOURCE = docs/spacemap.1.scd
APP_FONT_SOURCE = ../sketchybar-app-font/dist/sketchybar-app-font.ttf
APP_FONT_FALLBACK = $(HOME)/Library/Fonts/sketchybar-app-font.ttf
APP_FONT_RESOURCE = Sources/spacemap/Resources/sketchybar-app-font.ttf
MAN_PAGE = docs/spacemap.1
LOCALIZATION_DIRS = $(wildcard Sources/spacemap/Resources/*.lproj)
LOCALIZATION_NAMES = $(notdir $(LOCALIZATION_DIRS))

# The version of a release comes from the command line:
#   make release VERSION=1.2.3
# RELEASE=1.2.3 is the old spelling and still works.
ifeq ($(origin VERSION),command line)
RELEASE_VERSION := $(strip $(VERSION))
else
RELEASE_VERSION := $(strip $(RELEASE))
endif

.PHONY: help build test app app-arm app-intel app-universal \
	dmg dmg-arm dmg-intel dmg-universal release-artifacts release clean \
	install run dev uninstall config distconfig archive permissions \
	install-cli uninstall-cli build-arm64 build-x86_64 build-universal \
	app-arm64 app-x86_64 verify-localizations generate-xcodeproj man \
	update-app-font

.DEFAULT_GOAL := help

## help — list every target

help:
	@printf '%s\n' \
		'Spacemap — build targets.' \
		'' \
		'  help                 List every target (default).' \
		'  build                Build the release binary of the SwiftPM package.' \
		'  test                 Run the SwiftPM test suite.' \
		'  app                  Build the shipping bundle into Spacemap.app (universal).' \
		'  app-arm              Build an arm64 bundle into spacemap-arm64.app.' \
		'  app-intel            Build an x86_64 bundle into spacemap-x86_64.app.' \
		'  app-universal        Build a bundle with both architectures into Spacemap.app.' \
		'  dmg                  Build the disk images the tap installs (arm64 and x86_64).' \
		'  dmg-arm              Build spacemap-<version>-arm64.dmg from the arm64 bundle.' \
		'  dmg-intel            Build spacemap-<version>-x86_64.dmg from the x86_64 bundle.' \
		'  dmg-universal        Build spacemap-<version>-universal.dmg from the universal bundle.' \
		'  release-artifacts    Build the disk images and write checksums.txt for the tap.' \
		'  release VERSION=x.y.z  Build the artifacts, tag v<x.y.z> locally, print the push command.' \
		'  clean                Remove the build output.' \
		'' \
		'Notes' \
		'  The app bundle is assembled by hand from the SwiftPM build. `swift build`' \
		'  alone gives a bare executable without the resources the app needs.' \
		'  Spacemap builds for Apple silicon (arm64), for Intel (x86_64) and universal.' \
		'  The shipping bundle Spacemap.app is universal.' \
		'  The tap installs a disk image per architecture, so `make dmg` builds the' \
		'  arm64 and the x86_64 image. The universal image feeds the Sparkle appcast.' \
		'  Signing stays ad-hoc: codesign --force --sign - --options runtime.' \
		'  There is no Developer ID identity and no notarization.' \
		'  `make release VERSION=1.2.3` writes the VERSION file and the Info.plist,' \
		'  commits them, tags v1.2.3 locally and prints the command that pushes the' \
		'  commit and the tag. It never pushes by itself.' \
		'  The old names app-arm64, app-x86_64, dmg-arm64 and dmg-x86_64 still work.' \
		'  create-dmg is required for the dmg targets: brew install create-dmg.' \
		'  scdoc is required for the man page: brew install scdoc.'

# The bundled ttf is committed; this target refreshes it from a local checkout
# or an installed font. No network access.
update-app-font:
	@mkdir -p $(dir $(APP_FONT_RESOURCE))
	@if [ -f "$(APP_FONT_SOURCE)" ]; then \
		src="$(APP_FONT_SOURCE)"; \
	elif [ -f "$(APP_FONT_FALLBACK)" ]; then \
		src="$(APP_FONT_FALLBACK)"; \
	else \
		echo "ERROR: sketchybar-app-font.ttf not found at either:"; \
		echo "  $(APP_FONT_SOURCE)"; \
		echo "  $(APP_FONT_FALLBACK)"; \
		echo "Clone https://github.com/kvndrsslr/sketchybar-app-font or install the font first."; \
		exit 1; \
	fi; \
	cp "$$src" "$(APP_FONT_RESOURCE)" && \
	echo "Copied $$src -> $(APP_FONT_RESOURCE)"

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

# The toolchain writes every architecture into one product directory, so the
# per-architecture binary is copied aside before the next build overwrites it.
build-arm64:
	swift build -c release --arch arm64 --product $(BINARY_NAME)
	@if ! lipo -archs "$(BUILD_ARM64)/$(BINARY_NAME)" 2>/dev/null | grep -q arm64; then \
		mkdir -p $(BUILD_ARM64); \
		cp "$$(swift build -c release --arch arm64 --product $(BINARY_NAME) --show-bin-path 2>/dev/null | tail -1)/$(BINARY_NAME)" "$(BUILD_ARM64)/$(BINARY_NAME)"; \
	fi

build-x86_64:
	swift build -c release --arch x86_64 --product $(BINARY_NAME)
	@if ! lipo -archs "$(BUILD_X86_64)/$(BINARY_NAME)" 2>/dev/null | grep -q x86_64; then \
		mkdir -p $(BUILD_X86_64); \
		cp "$$(swift build -c release --arch x86_64 --product $(BINARY_NAME) --show-bin-path 2>/dev/null | tail -1)/$(BINARY_NAME)" "$(BUILD_X86_64)/$(BINARY_NAME)"; \
	fi

build-universal: build-arm64 build-x86_64
	mkdir -p .build/universal/release
	lipo -create -output .build/universal/release/$(BINARY_NAME) \
		$(BUILD_ARM64)/$(BINARY_NAME) \
		$(BUILD_X86_64)/$(BINARY_NAME)
	@echo "Universal binary: .build/universal/release/$(BINARY_NAME)"
	@lipo -info .build/universal/release/$(BINARY_NAME)

# The shipping bundle. Spacemap ships universal.
app: app-universal

app-arm: BUNDLE = $(APP_NAME)-arm64.app
app-arm: BIN_SRC = $(BUILD_ARM64)/$(BINARY_NAME)
app-arm: DONE_MSG = Built $(APP_NAME)-arm64.app (Apple Silicon)
app-arm: build-arm64 man
	@$(MAKE) --no-print-directory _assemble BUNDLE="$(BUNDLE)" BIN_SRC="$(BIN_SRC)" REQUIRE_SPARKLE_KEY=$(REQUIRE_SPARKLE_KEY)
	@echo "$(DONE_MSG)"

# The old name still works.
app-arm64: app-arm

app-intel: BUNDLE = $(APP_NAME)-x86_64.app
app-intel: BIN_SRC = $(BUILD_X86_64)/$(BINARY_NAME)
app-intel: DONE_MSG = Built $(APP_NAME)-x86_64.app (Intel)
app-intel: build-x86_64 man
	@$(MAKE) --no-print-directory _assemble BUNDLE="$(BUNDLE)" BIN_SRC="$(BIN_SRC)" REQUIRE_SPARKLE_KEY=$(REQUIRE_SPARKLE_KEY)
	@echo "$(DONE_MSG)"

app-x86_64: app-intel

app-universal: BUNDLE = $(APP_BUNDLE)
app-universal: BIN_SRC = .build/universal/release/$(BINARY_NAME)
app-universal: DONE_MSG = Built $(APP_BUNDLE) (Universal: arm64 + x86_64)
app-universal: build-universal man
	@$(MAKE) --no-print-directory _assemble BUNDLE="$(BUNDLE)" BIN_SRC="$(BIN_SRC)" REQUIRE_SPARKLE_KEY=$(REQUIRE_SPARKLE_KEY)
	@echo "$(DONE_MSG)"

_assemble:
	@test -n "$(BUNDLE)" || { echo "BUNDLE is required"; exit 1; }
	@test -n "$(BIN_SRC)" || { echo "BIN_SRC is required"; exit 1; }
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Frameworks
	mkdir -p $(BUNDLE)/Contents/Resources
	rm -f $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp $(BIN_SRC) $(BUNDLE)/Contents/MacOS/
	cp Sources/spacemap/Info.plist $(BUNDLE)/Contents/
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(BUNDLE)/Contents/Info.plist 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://wiggly-sheets.github.io/Spacemap/appcast.xml" $(BUNDLE)/Contents/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://wiggly-sheets.github.io/Spacemap/appcast.xml" $(BUNDLE)/Contents/Info.plist 2>/dev/null || true
	@if [ -n "$(SPARKLE_PUBLIC_KEY)" ]; then \
		/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(SPARKLE_PUBLIC_KEY)" $(BUNDLE)/Contents/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $(SPARKLE_PUBLIC_KEY)" $(BUNDLE)/Contents/Info.plist 2>/dev/null || true; \
	elif [ "$(REQUIRE_SPARKLE_KEY)" = "1" ] || echo " $(MAKECMDGOALS) " | grep -Eq ' (release|archive|dmg|dmg-arm|dmg-arm64|dmg-intel|dmg-x86_64|dmg-universal|release-artifacts)( |$$)'; then \
		echo "ERROR: SPARKLE_PUBLIC_KEY is empty — set env or sparklesigner.pub (required for release builds)"; exit 1; \
	else \
		echo "warning: SPARKLE_PUBLIC_KEY is empty — skipping SUPublicEDKey (dev build only; release builds require it)"; \
	fi
	# Copy Sparkle framework (extract from xcframework structure)
	@test -n "$(SPARKLE_FRAMEWORK)" || { echo "Sparkle.framework not found under .build/artifacts/sparkle/Sparkle/Sparkle.xcframework"; exit 1; }
	cp -R "$(SPARKLE_FRAMEWORK)" $(BUNDLE)/Contents/Frameworks/
	# Delete-first so rebuilds never fail on a duplicate rpath or accumulate copies.
	install_name_tool -delete_rpath "@executable_path/../Frameworks" $(BUNDLE)/Contents/MacOS/$(BINARY_NAME) 2>/dev/null || true
	install_name_tool -add_rpath "@executable_path/../Frameworks" $(BUNDLE)/Contents/MacOS/$(BINARY_NAME)
	cp Sources/spacemap/spacemap.icns $(BUNDLE)/Contents/Resources/spacemap.icns
	cp Sources/spacemap/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	cp Assets/AppIcon/Assets.car $(BUNDLE)/Contents/Resources/Assets.car
	cp -R $(LOCALIZATION_DIRS) $(BUNDLE)/Contents/Resources/
	cp $(MAN_PAGE) $(BUNDLE)/Contents/Resources/spacemap.1
	cp $(APP_FONT_RESOURCE) $(BUNDLE)/Contents/Resources/sketchybar-app-font.ttf
	@$(MAKE) --no-print-directory verify-localizations BUNDLE=$(BUNDLE)


verify-localizations:
	@test -n "$(BUNDLE)" || { echo "BUNDLE is required"; exit 1; }
	@test -n "$(LOCALIZATION_NAMES)" || { echo "No source localizations found"; exit 1; }
	@for locale in $(LOCALIZATION_NAMES); do \
		localization="$(BUNDLE)/Contents/Resources/$$locale/Localizable.strings"; \
		test -s "$$localization" || { \
			echo "Missing localization: $$localization"; \
			exit 1; \
		}; \
		/usr/bin/plutil -lint "$$localization" >/dev/null || exit 1; \
		if /usr/bin/grep -Eq '\\u[0-9A-Fa-f]{4}' "$$localization"; then \
			echo "Invalid lowercase Unicode escape in $$localization (use \\Uhhhh)"; \
			exit 1; \
		fi; \
	done
	@echo "Verified $(words $(LOCALIZATION_NAMES)) localizations in $(BUNDLE)"

# Release entry points require the Sparkle key. The value reaches _assemble
# via prerequisite inheritance plus explicit forwarding in app-* recipes.
archive dmg dmg-arm dmg-intel dmg-universal: REQUIRE_SPARKLE_KEY = 1

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
	@echo "Next: go to https://github.com/wiggly-sheets/Spacemap/releases/new"
	@echo "  1. Tag: v$(VERSION)"
	@echo "  2. Click 'Generate release notes'"
	@echo "  3. Attach $(ARCHIVE)"
	@echo "  4. No Homebrew step: wiggly-sheets/homebrew-tap renders its own cask from a template and follows the latest stable release"

# The disk images the tap installs: one per architecture. The universal
# image feeds the Sparkle appcast, not the tap.
dmg: dmg-arm dmg-intel

dmg-arm: app-arm
	@$(MAKE) _dmg INPUT=$(APP_NAME)-arm64.app OUTPUT=$(DMG_ARM)

# The old name still works.
dmg-arm64: dmg-arm

dmg-intel: app-intel
	@$(MAKE) _dmg INPUT=$(APP_NAME)-x86_64.app OUTPUT=$(DMG_INTEL)

dmg-x86_64: dmg-intel

dmg-universal: app-universal
	@$(MAKE) _dmg INPUT=$(APP_BUNDLE) OUTPUT=$(DMG_UNIV)

_dmg:
	@rm -rf $(DMG_STAGE)
	@# create-dmg refuses an existing file, so a rebuild starts from scratch.
	@rm -f $(OUTPUT)
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
	cp -R $(APP_CONTENTS)/Resources/*.lproj $(INSTALL_PATH)/Contents/Resources/
	cp $(MAN_PAGE) $(INSTALL_PATH)/Contents/Resources/spacemap.1
	cp $(APP_FONT_RESOURCE) $(INSTALL_PATH)/Contents/Resources/sketchybar-app-font.ttf
	@$(MAKE) --no-print-directory verify-localizations BUNDLE=$(INSTALL_PATH)
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
	# -f replaces the existing symlink so reinstalls stay idempotent.
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

# The files the tap expects: the disk images and the checksum file next to
# them. The tap matches the asset by name, so the names never change.
release-artifacts: dmg
	@shasum -a 256 $(DMG_ARM) $(DMG_INTEL) > checksums.txt
	@echo "checksums.txt:"
	@cat checksums.txt

# Prepare a release and tag it. The push is the release, and it belongs to
# the person who runs this target, so the target prints the command and
# stops there.
release:
	@if [ -z "$(RELEASE_VERSION)" ]; then \
		echo "error: make release needs a version, for example: make release VERSION=1.2.3"; \
		exit 1; \
	fi
	@# The generated assets are no reason to refuse the release.
	@if [ -n "$$(git status --porcelain | grep -vE '^\?\? (checksums\.txt|spacemap-.*\.dmg)$$')" ]; then \
		echo "error: the working tree is dirty. Commit or stash your changes first."; \
		git status --short; \
		exit 1; \
	fi
	@if git rev-parse -q --verify "refs/tags/v$(RELEASE_VERSION)" >/dev/null; then \
		echo "error: the tag v$(RELEASE_VERSION) already exists."; \
		exit 1; \
	fi
	@test -n "$(SPARKLE_PUBLIC_KEY)" || (echo "ERROR: SPARKLE_PUBLIC_KEY is empty — set env or sparklesigner.pub (required for release builds)" && exit 1)
	@# Auto-generate changelog entry from git diff
	@chmod +x scripts/generate-changelog.sh
	@scripts/generate-changelog.sh "$(RELEASE_VERSION)"
	@grep -q "$(RELEASE_VERSION)" CHANGELOG.md || (echo "ERROR: CHANGELOG.md has no entry for $(RELEASE_VERSION). Update it manually." && exit 1)
	@echo "Releasing v$(RELEASE_VERSION)..."
	@# Update Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(RELEASE_VERSION)" Sources/spacemap/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(RELEASE_VERSION)" Sources/spacemap/Info.plist
	@# Update VERSION file
	@echo "$(RELEASE_VERSION)" > VERSION
	@# Build before the commit, so a failed build leaves no commit behind.
	$(MAKE) release-artifacts VERSION=$(RELEASE_VERSION)
	@# Commit and tag. The tag stays local: the push is printed, never run.
	git add Sources/spacemap/Info.plist VERSION CHANGELOG.md
	git commit -m "v$(RELEASE_VERSION)"
	git tag -a "v$(RELEASE_VERSION)" -m "Spacemap $(RELEASE_VERSION)"
	@echo ""
	@echo "Tagged v$(RELEASE_VERSION). Push the commit and the tag with:"
	@echo "  git push origin main --tags"

# Remove the build output.
clean:
	rm -rf .build $(APP_BUNDLE) $(APP_NAME)-arm64.app $(APP_NAME)-x86_64.app
	rm -rf $(DMG_STAGE) $(STAGE)
	rm -f $(APP_NAME)-*.dmg checksums.txt $(ARCHIVE)

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
