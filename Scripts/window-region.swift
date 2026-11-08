// Prints "x,y,w,h" covering all on-screen windows of a process, with room for shadows.
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1])!
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var region = CGRect.null
var count = 0
for window in info where window[kCGWindowOwnerPID as String] as? Int32 == pid && window[kCGWindowLayer as String] as? Int == 25 {
    if let bounds = window[kCGWindowBounds as String], let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) {
        region = region.union(rect)
        count += 1
    }
}
let padded = region.insetBy(dx: -32, dy: -32)
print("\(Int(padded.minX)),\(Int(padded.minY)),\(Int(padded.width)),\(Int(padded.height))")
FileHandle.standardError.write(Data("windows=\(count)\n".utf8))
