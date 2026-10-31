#if DEBUG
import AppKit

/// With the launch argument `-debugDumpMenus <path>`, the app menu and the
/// menu bar item's menu are written to that file as text a second after
/// launch, once SwiftUI has built its menus: they can't be read otherwise
/// without Accessibility permission
enum DebugDump {
    static func scheduleIfAsked(statusMenu: NSMenu?) {
        guard let path = UserDefaults.standard.string(forKey: "debugDumpMenus") else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            var lines: [String] = []
            for item in NSApp.mainMenu?.items ?? [] {
                lines.append(item.submenu?.title ?? item.title)
                describe(item.submenu, depth: 1, into: &lines)
            }
            lines.append("[status item]")
            describe(statusMenu, depth: 1, into: &lines)
            try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static func describe(_ menu: NSMenu?, depth: Int, into lines: inout [String]) {
        for item in menu?.items ?? [] {
            let indent = String(repeating: "  ", count: depth)
            if item.isSeparatorItem {
                lines.append(indent + "---")
                continue
            }
            var line = indent + item.title
            if !item.keyEquivalent.isEmpty {
                line += "  " + shortcut(item)
            }
            if item.state == .on { line += "  [on]" }
            if !item.isEnabled { line += "  [disabled]" }
            if item.isHidden { line += "  [hidden]" }
            lines.append(line)
            if let submenu = item.submenu, depth < 2 {
                describe(submenu, depth: depth + 1, into: &lines)
            }
        }
    }

    private static func shortcut(_ item: NSMenuItem) -> String {
        let flags = item.keyEquivalentModifierMask
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) || item.keyEquivalent != item.keyEquivalent.lowercased() { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + item.keyEquivalent.uppercased()
    }
}
#endif
