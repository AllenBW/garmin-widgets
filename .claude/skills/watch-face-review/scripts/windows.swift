import CoreGraphics
import Foundation
// Prints the window id of the Connect IQ simulator's device window
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list {
    let owner = w["kCGWindowOwnerName"] as? String ?? ""
    let name = w["kCGWindowName"] as? String ?? ""
    let num = w["kCGWindowNumber"] as? Int ?? 0
    if owner == "Connect IQ Device Simulator" && name.hasPrefix("CIQ Simulator") { print(num) }
}
