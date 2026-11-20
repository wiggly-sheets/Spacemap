import SwiftUI
import Foundation
import CoreGraphics
import AppKit
import Combine
import Sparkle

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
    /// Position-only strip change (a drag). Unlike `.settingsChanged` this must
    /// not reload themes or drop the glyph-font cache.
    static let glyphStripPositionChanged = Notification.Name("glyphStripPositionChanged")
    /// Active space-name profile changed from the menu bar. Re-seeds only the
    /// profile state in an open Settings window.
    static let spaceNameProfileChanged = Notification.Name("spaceNameProfileChanged")
}


struct SettingsView: View {
    enum SidebarSection: String, CaseIterable, Identifiable {
        case general = "General"
        case spaces = "Spaces"
        case hud = "HUD"
        case glyphStrip = "Glyph Strip"
        case hotkeys = "Hotkeys"
        case advanced = "Advanced"

        var id: String { rawValue }
    }

    /// One editing session over the whole config; every control binds a field.
    @ObservedObject var draft: SettingsDraft

    /// Coordinate space the detail pane's section anchors report into.
    static let detailSpace = "settingsDetail"
    @State private var selectedSection: SidebarSection = .general
    @State private var currentSubsection: String?
    @State private var scrollTarget: String?
    @State private var scrollToken = 0
    /// Scroll tracking pauses briefly after a click so the pane's old offset
    /// cannot pull the highlight back to the section it just left.
    @State private var trackingSuppressed = false
    @State private var isYabaiHealthy: Bool?
    @State private var isSocketHealthy: Bool?
    @State private var isRefreshingDiagnostics = false
    @State private var autoSpaceNames: [Int: String] = [:]

    private let yabaiService: YabaiService
    private let themeStore: ThemeStore
    private let themeCatalog: ThemeCatalogService
    private let diagnosticsTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(
        yabaiService: YabaiService,
        themeStore: ThemeStore,
        themeCatalog: ThemeCatalogService,
        draft: SettingsDraft
    ) {
        self.yabaiService = yabaiService
        self.themeStore = themeStore
        self.themeCatalog = themeCatalog
        _draft = ObservedObject(wrappedValue: draft)
    }

    static let saveFailureMessage = NSLocalizedString(
        "Spacemap could not write its configuration file. Check permissions and try again.",
        comment: "Settings save failure message"
    )

    static func saveResultMessage(_ success: Bool) -> String? {
        success ? nil : saveFailureMessage
    }

    /// Ignore offset updates until a programmatic scroll has landed.
    private func suppressTracking() {
        trackingSuppressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            trackingSuppressed = false
        }
    }

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(
                selectedSection: $selectedSection,
                currentSubsection: $currentSubsection,
                onSelectSection: { section in
                    guard let first = section.subsections.first else { return }
                    suppressTracking()
                    scrollTarget = first.id
                    scrollToken += 1
                    currentSubsection = first.id
                },
                onSelectSubsection: { subsection in
                    suppressTracking()
                    scrollTarget = subsection.id
                    scrollToken += 1
                    currentSubsection = subsection.id
                }
            )
        } detail: {
            ScrollViewReader { proxy in
            Form {
                switch selectedSection {
            case .general:
                behaviorPane(.general)

            case .spaces:
                SettingsGrid(
                    maxSpaces: draft.binding(\.maxSpaces),
                    gridLayoutIndex: $draft.gridLayoutIndex,
                    cols: draft.binding(\.cols),
                    rows: draft.binding(\.rows),
                    showMode: draft.binding(\.showMode),
                    multiMonitorHUDMode: draft.binding(\.multiMonitorHUDMode),
                    unifiedHUDVisibility: draft.binding(\.unifiedHUDVisibility),
                    separateHUDVisibility: draft.binding(\.separateHUDVisibility),
                    cellStyle: draft.binding(\.cellStyle),
                    showSpaceNumbers: draft.binding(\.showSpaceNumbers),
                    showSpaceLayout: draft.binding(\.showSpaceLayout),
                    showBSPLayoutBadge: draft.binding(\.showBSPLayoutBadge),
                    showStackLayoutBadge: draft.binding(\.showStackLayoutBadge),
                    showFloatLayoutBadge: draft.binding(\.showFloatLayoutBadge),
                    showIconStrip: draft.binding(\.showIconStrip),
                    showMultiAppIcons: draft.binding(\.showMultiAppIcons),
                    hudIconSource: draft.binding(\.hudIconSource),
                    hudIconStripSeparate: draft.binding(\.hudIconStripSeparate),
                    hudIconStripSource: draft.binding(\.hudIconStripSource),
                    showThumbnailWallpaper: draft.binding(\.showThumbnailWallpaper)
                )
                SettingsSpaceNames(
                    showSpaceNames: draft.binding(\.showSpaceNames),
                    spaceNameInputs: draft.binding(\.spaceNames),
                    maxSpaces: draft.binding(\.maxSpaces),
                    profiles: draft.binding(\.spaceNameProfiles),
                    activeProfileIndex: draft.binding(\.activeSpaceNameProfileIndex),
                    namingMode: draft.binding(\.namingMode),
                    autoNameAppCount: draft.binding(\.autoNameAppCount),
                    autoSpaceNames: autoSpaceNames
                )

            case .hud:
                appearancePane
                behaviorPane(.hud)

            case .glyphStrip:
                SettingsGlyphStrip(
                    glyphStrip: draft.binding(\.glyphStrip),
                    themeName: draft.config.theme,
                    themeStore: themeStore
                )

            case .hotkeys:
                behaviorPane(.hotkeys)

            case .advanced:
                SettingsAdvanced(
                    isYabaiHealthy: $isYabaiHealthy,
                    isSocketHealthy: $isSocketHealthy,
                    isRefreshingDiagnostics: $isRefreshingDiagnostics,
                    socketHealthInterval: draft.binding(\.socketHealthInterval),
                    showExtraWindows: draft.binding(\.showExtraWindows),
                    refreshDiagnostics: refreshDiagnostics,
                    flush: draft.flush
                )
                }
            }
            .id(selectedSection)
            .coordinateSpace(name: Self.detailSpace)
            .onPreferenceChange(SettingsSectionOffsetKey.self) { offsets in
                guard !trackingSuppressed else { return }
                // Only this pane's anchors count. A rebuilt Form can report
                // the previous pane's offsets for a frame, and those must not
                // steal the highlight back to another section.
                let ids = Set(selectedSection.subsections.map(\.id))
                let scoped = offsets.filter { ids.contains($0.key) }
                guard !scoped.isEmpty else { return }
                // The section whose header is the last one to cross the top
                // band is the one being read; before any header reaches it,
                // the nearest header wins.
                let passed = scoped.filter { $0.value <= 120 }
                let active = passed.max { $0.value < $1.value }?.key
                    ?? scoped.min { $0.value < $1.value }?.key
                if let active, active != currentSubsection {
                    currentSubsection = active
                }
            }
            .onChange(of: scrollToken) { _ in
                guard let target = scrollTarget else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.clear)
        .onChange(of: selectedSection) { section in
            draft.flush()
            if section == .advanced { refreshDiagnostics() }
            if section == .spaces { refreshAutoSpaceNames() }
        }
        .onChange(of: draft.config.namingMode) { _ in
            refreshAutoSpaceNames()
        }
        .onReceive(diagnosticsTimer) { _ in
            if selectedSection == .advanced { refreshDiagnostics() }
            if selectedSection == .spaces { refreshAutoSpaceNames() }
        }
        .alert(
            "Could not save settings",
            isPresented: Binding(
                get: { draft.saveErrorMessage != nil },
                set: { if !$0 { draft.saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(draft.saveErrorMessage ?? "")
        }
        .formStyle(.grouped)
        .frame(minWidth: 500)
    }

    private func behaviorPane(_ scope: SettingsBehavior.Scope) -> some View {
        SettingsBehavior(
            hotkeyString: draft.hotkeyStringBinding,
            pinnedHotkeyString: draft.pinnedHotkeyStringBinding,
            glyphStripHotkeyString: draft.glyphStripHotkeyStringBinding,
            hudKeys: draft.binding(\.hudKeys),
            hudPositionKind: draft.hudPositionKindBinding,
            autoHideTimeout: draft.binding(\.autoHideTimeout),
            jumpToSpaceEnabled: draft.binding(\.jumpToSpaceEnabled),
            displayNavigationWrap: draft.binding(\.displayNavigationWrap),
            focusSpaceOnWindowDrop: draft.binding(\.focusSpaceOnWindowDrop),
            focusSpaceOnWindowDropModifier: draft.binding(\.focusSpaceOnWindowDropModifier),
            showHUDOnSpaceChange: draft.binding(\.showHUDOnSpaceChange),
            showHUDInteractionFeedback: draft.binding(\.showHUDInteractionFeedback),
            hudAnimationsEnabled: draft.binding(\.hudAnimationsEnabled),
            hudAnimationStyle: draft.binding(\.hudAnimationStyle),
            hudEntranceStyle: draft.binding(\.hudEntranceStyle),
            presence: draft.binding(\.presence),
            menuBarDisplayMode: draft.binding(\.menuBarDisplayMode),
            menuBarNearbyCount: draft.binding(\.menuBarNearbyCount),
            glyphStripMenuBarItem: draft.glyphStripMenuBarItemBinding,
            updateMode: draft.binding(\.updateMode),
            appFontUpdateMode: draft.appFontUpdateModeBinding,
            checkForUpdates: { (NSApp.delegate as? AppDelegate)?.checkForUpdates() },
            scope: scope
        )
    }

    private var appearancePane: some View {
        SettingsAppearanceView(
                    theme: draft.binding(\.theme),
                    mode: draft.binding(\.mode),
                    backgroundAlpha: draft.binding(\.backgroundAlpha),
                    backgroundStyle: draft.binding(\.backgroundStyle),
                    glassStyle: draft.binding(\.glassStyle),
                    glassClearVariant: draft.binding(\.glassClearVariant),
                    glassRegularVariant: draft.binding(\.glassRegularVariant),
                    glassTintedVariant: draft.binding(\.glassTintedVariant),
                    glassTintedMaterial: draft.binding(\.glassTintedMaterial),
                    glassClearOpacity: draft.binding(\.glassClearOpacity),
                    glassRegularOpacity: draft.binding(\.glassRegularOpacity),
                    glassTintedOpacity: draft.binding(\.glassTintedOpacity),
                    solidOpacity: draft.binding(\.solidOpacity),
                    matchBackgroundOpacity: draft.binding(\.matchBackgroundOpacity),
                    hudShadow: draft.binding(\.hudShadow),
                    hudCornerRadius: draft.binding(\.hudCornerRadius),
                    hudFontName: draft.binding(\.hudFontName),
                    hudFontSize: draft.binding(\.hudFontSize),
                    hudTextColor: draft.binding(\.hudTextColor),
                    iconScale: draft.binding(\.iconScale),
                    uiScale: draft.binding(\.uiScale),
                    spacesMatchBackground: draft.binding(\.spacesMatchBackground),
                    spacesBackgroundStyle: draft.binding(\.spacesBackgroundStyle),
                    spacesGlassStyle: draft.binding(\.spacesGlassStyle),
                    spacesGlassClearVariant: draft.binding(\.spacesGlassClearVariant),
                    spacesGlassRegularVariant: draft.binding(\.spacesGlassRegularVariant),
                    spacesGlassTintedVariant: draft.binding(\.spacesGlassTintedVariant),
                    spacesGlassTintedMaterial: draft.binding(\.spacesGlassTintedMaterial),
                    spacesOpacity: draft.binding(\.spacesOpacity),
                    spacesCornerRadius: draft.binding(\.spacesCornerRadius),
                    themeStore: themeStore,
                    themeCatalog: themeCatalog
                )
    }

    /// Derived names are read-only, so the settings pane shows what the HUD
    /// renders instead of graying out the stored custom names.
    private func refreshAutoSpaceNames() {
        let config = draft.config
        guard config.namingMode == .auto else { return }
        yabaiService.runOnYabaiQueue {
            let names = yabaiService.buildGridState(config: config, focusedIndex: nil).resolvedSpaceNames
            DispatchQueue.main.async {
                autoSpaceNames = names
            }
        }
    }

    private func refreshDiagnostics() {
        guard !isRefreshingDiagnostics else { return }
        isRefreshingDiagnostics = true
        let socketPath = SpacemapCommand.socketPath
        yabaiService.runOnYabaiQueue {
            let yabaiHealthy = yabaiService.isYabaiRunning(forceRefresh: true)
            let socketHealthy = SocketListener.sendCommand(to: socketPath, command: 5)
            DispatchQueue.main.async {
                isYabaiHealthy = yabaiHealthy
                isSocketHealthy = socketHealthy
                isRefreshingDiagnostics = false
            }
        }
    }
}
