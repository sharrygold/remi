// Prints "x,y,w,h" covering all on-screen windows of a process, with room for shadows.
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1])!
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var region = CGRect.null
var count = 0
for window in info where window[kCGWindowOwnerPID as String] as? Int32 == pid {
    // The menu bar item is also this process's window; it is the only one under 40 pt tall.
    if let bounds = window[kCGWindowBounds as String], let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary), rect.height >= 40 {
        region = region.union(rect)
        count += 1
    }
}
guard count > 0 else {
    FileHandle.standardError.write(Data("no windows found\n".utf8))
    exit(1)
}
let padded = region.insetBy(dx: -32, dy: -32)
print("\(Int(padded.minX)),\(Int(padded.minY)),\(Int(padded.width)),\(Int(padded.height))")
FileHandle.standardError.write(Data("windows=\(count)\n".utf8))
