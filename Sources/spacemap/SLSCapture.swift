import Foundation
import CoreGraphics

/// Dynamically loads and calls the private SLSHWCaptureSpace function to capture a Mission Control space.
/// Uses `dlopen` + `dlsym` to avoid linking issues with private APIs.
/// Based on sketchybar's space_capture() implementation.
struct SLSCapture {
    
    /// Capture a space and return a CGImage, or nil if capture fails.
    static func capture(spaceIndex: Int, displayBounds: CGRect) -> CGImage? {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY) else {
            return nil
        }
        defer { dlclose(handle) }
        
        guard let copyDisplaySpacesSym = dlsym(handle, "SLSCopyManagedDisplaySpaces"),
              let captureSpaceSym = dlsym(handle, "SLSHWCaptureSpace") else {
            return nil
        }
        
        typealias CopyDisplaySpacesFunc = @convention(c) (Int32) -> CFArray
        typealias CaptureSpaceFunc = @convention(c) (Int64, Int64, Int64) -> CFArray
        
        let copyFunc = unsafeBitCast(copyDisplaySpacesSym, to: CopyDisplaySpacesFunc.self)
        let captureFunc = unsafeBitCast(captureSpaceSym, to: CaptureSpaceFunc.self)
        
        // Get display spaces (all Mission Control spaces across all displays)
        let displaySpaces = copyFunc(-1)
        
        // dsid_from_sid: linear scan through display→spaces to find dsid for this space index
        var desktopCount: Int32 = 1
        var dsid: Int64 = 0
        
        let displayCount = CFArrayGetCount(displaySpaces)
        outerLoop: for i in 0..<displayCount {
            let displayPtr = CFArrayGetValueAtIndex(displaySpaces, i)
            let display = Unmanaged<CFDictionary>.fromOpaque(displayPtr!).takeUnretainedValue()
            let spaces = CFDictionaryGetValue(display, Unmanaged.passUnretained("Spaces" as CFString).toOpaque())
            guard let spacesArr = spaces else { continue }
            let spacesRef = unsafeBitCast(spacesArr, to: CFArray.self)
            let spaceCount = CFArrayGetCount(spacesRef)
            
            for j in 0..<spaceCount {
                let spacePtr = CFArrayGetValueAtIndex(spacesRef, j)
                let space = Unmanaged<CFDictionary>.fromOpaque(spacePtr!).takeUnretainedValue()
                let id64Ptr = CFDictionaryGetValue(space, Unmanaged.passUnretained("id64" as CFString).toOpaque())
                guard let id64Num = id64Ptr else { continue }
                let id64 = Unmanaged<CFNumber>.fromOpaque(id64Num).takeUnretainedValue()
                var foundDSID: Int64 = 0
                CFNumberGetValue(id64, CFNumberGetType(id64), &foundDSID)
                
                if desktopCount == Int32(spaceIndex) {
                    dsid = foundDSID
                    break outerLoop
                }
                desktopCount += 1
            }
        }
        
        guard dsid != 0 else { return nil }
        
        // Capture space
        let result = captureFunc(-1, dsid, 0)
        guard CFArrayGetCount(result) > 0 else { return nil }
        
        let imgPtr = CFArrayGetValueAtIndex(result, 0)
        let cgImage = Unmanaged<CGImage>.fromOpaque(imgPtr!).takeUnretainedValue()
        return cgImage.copy()
    }
}