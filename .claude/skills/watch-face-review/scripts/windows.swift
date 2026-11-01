import CoreGraphics
import Foundation
// Prints the window id of the Connect IQ simulator's device window; with a
// process id (windows <pid>), only that simulator's (scripts/simprivate.sh)
let only = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) : nil
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list {
    let owner = w["kCGWindowOwnerName"] as? String ?? ""
    let name = w["kCGWindowName"] as? String ?? ""
    let num = w["kCGWindowNumber"] as? Int ?? 0
    let pid = w["kCGWindowOwnerPID"] as? Int ?? 0
    // the private copy may carry its program's name as the owner, so match it by process
    let sim = only != nil ? only == pid : owner == "Connect IQ Device Simulator"
    if sim && name.hasPrefix("CIQ Simulator") { print(num) }
}
