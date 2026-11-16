import SwiftUI
import AppKit

/// Floating browser for bundled and downloadable themes.
final class ThemeLibraryWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ThemeLibraryWindowController()

    private var onApply: ((String) -> Void)?
    private var currentTheme = ""

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Theme Library"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.minSize = NSSize(width: 640, height: 440)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(currentTheme: String, onApply: @escaping (String) -> Void) {
        self.onApply = onApply
        self.currentTheme = currentTheme
        guard let window else { return }
        window.contentView = NSHostingView(rootView: ThemeLibraryView(
            currentTheme: currentTheme
        ) { [weak self] name in
            self?.currentTheme = name
            self?.onApply?(name)
        })
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ThemeLibraryView: View {
    @ObservedObject private var catalog = ThemeCatalogService.shared
    @State private var search = ""
    @State private var showInstalledOnly = false
    @State private var busy: String?
    @State private var errorMessage: String?

    @State private var currentTheme: String
    let onApply: (String) -> Void

    init(currentTheme: String, onApply: @escaping (String) -> Void) {
        _currentTheme = State(initialValue: currentTheme)
        self.onApply = onApply
    }

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", installed = "Installed", available = "Available"
        var id: String { rawValue }
    }
    @State private var filter: Filter = .all

    private var visible: [ThemeCatalogEntry] {
        catalog.entries.filter { entry in
            let installed = catalog.isInstalled(entry)
            guard filter != .installed || installed else { return false }
            guard filter != .available || !installed else { return false }
            let query = search.trimmingCharacters(in: .whitespaces)
            return query.isEmpty || entry.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search themes", text: $search)
                    .textFieldStyle(.plain)
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                Button {
                    Task { await catalog.refresh(manual: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh theme catalog")
                .disabled(catalog.isLoading)
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(visible) { entry in
                        card(entry)
                    }
                }
                .padding(14)
            }

            if let message = errorMessage ?? catalog.lastError {
                Divider()
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .task { catalog.start() }
    }

    private func card(_ entry: ThemeCatalogEntry) -> some View {
        let theme = entry.theme ?? .default
        let installed = catalog.isInstalled(entry)
        let bundled = catalog.isBundled(entry)
        return VStack(alignment: .leading, spacing: 10) {
            preview(theme)
                .frame(height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Text(entry.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if bundled {
                    Text("Bundled").font(.caption2).foregroundStyle(.secondary)
                } else if installed {
                    Text("Installed").font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                let applied = ThemeManager.normalizedName(currentTheme)
                    == ThemeManager.normalizedName(entry.name)
                Button(applied ? "Applied" : (installed ? "Apply" : "Install")) {
                    Task { await installOrApply(entry) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy == entry.id || applied)

                if installed && !bundled {
                    Button("Remove") { remove(entry) }
                        .buttonStyle(.bordered)
                        .disabled(busy == entry.id)
                }
                Spacer()
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func preview(_ theme: AppTheme) -> some View {
        ZStack {
            Color(hex: theme.background)
            HStack(spacing: 6) {
                swatch(theme.rect1, 26)
                swatch(theme.rect2, 26)
                swatch(theme.rect3, 26)
            }
            .padding(.leading, 8)
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: theme.cellBgFocused))
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: theme.cellBg))
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: theme.focused))
                    .frame(height: 6)
            }
            .padding(.leading, 110)
            .padding(.trailing, 10)
        }
    }

    private func swatch(_ value: UInt32, _ size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: value))
            .frame(width: size, height: size)
    }

    private func installOrApply(_ entry: ThemeCatalogEntry) async {
        if catalog.isInstalled(entry) {
            currentTheme = entry.name
            onApply(entry.name)
            return
        }
        busy = entry.id
        errorMessage = nil
        do {
            try await catalog.install(entry)
            currentTheme = entry.name
            onApply(entry.name)
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = nil
    }

    private func remove(_ entry: ThemeCatalogEntry) {
        busy = entry.id
        errorMessage = nil
        do {
            try catalog.uninstall(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = nil
    }
}
