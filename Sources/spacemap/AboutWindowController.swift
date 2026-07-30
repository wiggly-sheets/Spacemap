import AppKit

final class AboutWindowController: NSWindowController, NSWindowDelegate {
    private let onCheckForUpdates: () -> Void
    private let onClose: () -> Void
    private let tabs = NSTabViewController()

    init(onCheckForUpdates: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onCheckForUpdates = onCheckForUpdates
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Spacemap"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func makeContentView() -> NSView {
        let root = NSVisualEffectView()
        root.material = .windowBackground
        root.blendingMode = .behindWindow
        root.state = .active

        let icon = NSImageView(image: NSApplication.shared.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = label(
            "Spacemap \(Self.versionText)",
            font: .systemFont(ofSize: 24, weight: .semibold)
        )
        title.alignment = .left

        let header = NSStackView(views: [icon, title])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        header.translatesAutoresizingMaskIntoConstraints = false

        tabs.tabStyle = .segmentedControlOnTop
        tabs.addTabViewItem(tab(title: "About", content: aboutTab()))
        tabs.addTabViewItem(tab(title: "Contributors", content: contributorsTab()))
        tabs.addTabViewItem(tab(title: "License", content: licenseTab()))
        tabs.addTabViewItem(tab(title: "Software Used", content: softwareTab()))
        tabs.view.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(tabs.view)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),

            tabs.view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            tabs.view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            tabs.view.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            tabs.view.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])

        return root
    }

    private func aboutTab() -> NSView {
        let description = wrappingLabel(
            "A native macOS workspace map for yabai. Spacemap visualizes spaces in a "
                + "configurable grid and provides keyboard navigation, window movement, "
                + "live previews, themes, and automation-friendly controls."
        )

        let lineage = wrappingLabel(
            "This independently maintained project is a fork of jsheffie/Spacemap."
        )
        lineage.textColor = .secondaryLabelColor

        let copyright = label(
            Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
                ?? "Copyright © 2026 Wiggly-Sheets",
            font: .systemFont(ofSize: 12)
        )
        copyright.textColor = .secondaryLabelColor

        let repository = button("GitHub Repository", action: #selector(openRepository))
        let original = button("Original Project", action: #selector(openOriginalRepository))
        let updates = button("Check for Updates…", action: #selector(checkForUpdates))
        updates.keyEquivalent = "\r"

        return panel(
            views: [
                description,
                lineage,
                copyright,
                buttonRow(repository, original),
                fixedWidthButton(updates),
            ]
        )
    }

    private func contributorsTab() -> NSView {
        let heading = label("Project contributors", font: .systemFont(ofSize: 17, weight: .semibold))
        heading.alignment = .left

        let contributors = wrappingLabel(
            """
            Wiggly-Sheets — current maintainer and primary contributor

            Jeff Sheffield (jsheffie) — original creator of Spacemap

            Community contributors — translations, testing, issue reports, and improvements
            """
        )

        let lineage = wrappingLabel(
            "Spacemap continues as an independent fork with gratitude to the original "
                + "jsheffie/Spacemap project and everyone who contributed to its foundation."
        )
        lineage.textColor = .secondaryLabelColor

        let original = fixedWidthButton(
            button("View Original Repository", action: #selector(openOriginalRepository))
        )

        return panel(views: [heading, contributors, lineage, original])
    }

    private func licenseTab() -> NSView {
        let summary = wrappingLabel(
            "Spacemap is free and open-source software distributed under the MIT License."
        )

        let scroll = Self.makeLicenseScrollView()

        let onlineLicense = fixedWidthButton(
            button("View License on GitHub", action: #selector(openLicense))
        )

        return panel(views: [summary, scroll, onlineLicense])
    }

    static func makeLicenseScrollView() -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        guard let licenseText = scroll.documentView as? NSTextView else {
            return scroll
        }
        licenseText.string = mitLicense
        licenseText.isEditable = false
        licenseText.isSelectable = true
        licenseText.drawsBackground = false
        licenseText.textColor = .labelColor
        licenseText.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        licenseText.textContainerInset = NSSize(width: 8, height: 8)
        licenseText.isHorizontallyResizable = false
        licenseText.isVerticallyResizable = true
        licenseText.autoresizingMask = [.width]
        licenseText.textContainer?.widthTracksTextView = true

        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: 520),
            scroll.heightAnchor.constraint(equalToConstant: 220),
        ])
        return scroll
    }

    private func softwareTab() -> NSView {
        let heading = label("Open-source software used", font: .systemFont(ofSize: 17, weight: .semibold))
        heading.alignment = .left

        let sparkle = wrappingLabel(
            "Sparkle 2 — secure application updates for macOS\n"
                + "Copyright © Sparkle Project contributors\n"
                + "Distributed under the MIT License"
        )

        let system = wrappingLabel(
            "Spacemap is otherwise built with Apple system frameworks, including AppKit, "
                + "SwiftUI, Core Graphics, Application Services, and ScreenCaptureKit."
        )
        system.textColor = .secondaryLabelColor

        return panel(
            views: [
                heading,
                sparkle,
                buttonRow(
                    button("Sparkle Project", action: #selector(openSparkle)),
                    button("Sparkle License", action: #selector(openSparkleLicense))
                ),
                system,
            ]
        )
    }

    private func tab(title: String, content: NSView) -> NSTabViewItem {
        let controller = NSViewController()
        controller.view = content
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        return item
    }

    private func panel(views: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 10
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)

        if let contentView = box.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
                stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22),
            ])
        }

        return box
    }

    private func label(_ text: String, font: NSFont) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        return field
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let field = label(text, font: .systemFont(ofSize: 13))
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.preferredMaxLayoutWidth = 520
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func buttonRow(_ leading: NSButton, _ trailing: NSButton) -> NSStackView {
        let row = NSStackView(views: [leading, trailing])
        row.orientation = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 310).isActive = true
        return row
    }

    private func fixedWidthButton(_ button: NSButton) -> NSButton {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 200).isActive = true
        return button
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info["CFBundleVersion"] as? String
        if let build, build != version {
            return "v\(version) (\(build))"
        }
        return "v\(version)"
    }

    private static let mitLicense = """
    MIT License

    Copyright (c) 2026 Wiggly-Sheets

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """

    @objc private func openRepository() {
        open("https://github.com/wiggly-sheets/Spacemap")
    }

    @objc private func openOriginalRepository() {
        open("https://github.com/jsheffie/spacemap")
    }

    @objc private func openLicense() {
        open("https://github.com/wiggly-sheets/Spacemap/blob/main/LICENSE")
    }

    @objc private func openSparkle() {
        open("https://github.com/sparkle-project/Sparkle")
    }

    @objc private func openSparkleLicense() {
        open("https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }
}
