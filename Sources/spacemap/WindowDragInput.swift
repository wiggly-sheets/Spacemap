import Cocoa

struct WindowDragInput {
    var cellFrames: [(spaceIndex: Int, frame: CGRect)]
    var cachedWindows: [YabaiWindow]
    var focusedWindowIDAtOpen: Int?
}
