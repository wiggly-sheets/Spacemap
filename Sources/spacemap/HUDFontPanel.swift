import AppKit

/// Native font-panel bridge for the HUD font row. NSFontPanel sends
/// `changeFont:` to its target, so the controller stays alive and forwards the
/// selected family and point size to SwiftUI.
final class HUDFontPanel: NSObject {
    static let shared = HUDFontPanel()

    private var onChange: ((String, Double) -> Void)?

    func present(name: String, size: Double, onChange: @escaping (String, Double) -> Void) {
        self.onChange = onChange
        let font = NSFont(name: name, size: CGFloat(size)) ?? .systemFont(ofSize: CGFloat(size))
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(font, isMultiple: false)
        NSFontPanel.shared.setPanelFont(font, isMultiple: false)
        NSFontPanel.shared.orderFront(nil)
    }

    @objc private func changeFont(_ sender: NSFontManager) {
        guard let font = sender.selectedFont else { return }
        onChange?(font.fontName, Double(font.pointSize))
    }
}
