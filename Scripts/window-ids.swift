// Prints the window IDs of a process's on-screen windows taller than 40 pt, one per line,
// for `screencapture -l` (captures the window alone, on a transparent background).
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1])!
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in info where window[kCGWindowOwnerPID as String] as? Int32 == pid {
    if let bounds = window[kCGWindowBounds as String], let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary), rect.height >= 40,
       let id = window[kCGWindowNumber as String] as? Int {
        print("\(id) \(Int(rect.width))x\(Int(rect.height))")
    }
}
