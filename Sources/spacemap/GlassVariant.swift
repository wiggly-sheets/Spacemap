import AppKit

#if compiler(>=6.2)
/// The private Liquid Glass finishes on `NSGlassEffectView`, set only when the
/// setter exists and the value is one probed safe, then read back.
///
/// AppKit aborts outside the safe range, and macOS 27.2 draws every variant
/// from 22 up like variant 0, so nothing else is ever set. When the setter is
/// missing or the value does not stick, the view keeps its public style.
@available(macOS 26.0, *)
enum GlassVariant {
    static let variantKey = "_variant"
    static let safeVariants: ClosedRange<Int> = 0 ... 21

    @discardableResult
    static func apply(_ variant: Int?, to view: NSGlassEffectView) -> Bool {
        guard view.responds(to: NSSelectorFromString("set\(variantKey):")) else {
            return variant == nil
        }
        let target = variant ?? 0
        guard safeVariants.contains(target) else {
            if read(view) != 0 {
                view.setValue(0, forKey: variantKey)
            }
            return false
        }
        guard read(view) != target else { return true }
        view.setValue(target, forKey: variantKey)
        guard read(view) == target else {
            view.setValue(0, forKey: variantKey)
            return false
        }
        return true
    }

    /// The finish that makes clear glass read as a thin lens instead of the
    /// frosted regular material at a lower opacity.
    static let sheer: Int = 15

    private static func read(_ view: NSGlassEffectView) -> Int? {
        (view.value(forKey: variantKey) as? NSNumber)?.intValue
    }
}
#endif
