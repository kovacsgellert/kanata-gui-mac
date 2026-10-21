import AppKit
import SwiftUI

/// Menu-bar status icon for kanata's on/off state.
///
/// `MenuBarExtra(systemImage:)` can only show stock SF Symbols, and none of the
/// obvious candidates work at menu-bar size: `keyboard` and `keyboard.fill` are
/// nearly identical, `keyboard.slash` does not exist, and
/// `keyboard.badge.exclamationmark` (the old error icon) is missing on current
/// macOS, so that state rendered a blank icon.
///
/// So we compose our own template images instead: the keyboard glyph comes from
/// SF Symbols, and the "off" / "error" marks are drawn on top with a cut-out
/// gap, so both shapes stay legible at 16px and the icon inverts correctly with
/// the menu bar (light/dark, click highlight).
enum MenuBarIcon {
    /// Canvas, in points. Menu-bar icons live at ~16-18pt.
    static let pointSize = NSSize(width: 18, height: 18)

    /// Glyph size, chosen a little smaller than the canvas so the slash and the
    /// warning badge have room to breathe.
    private static let glyphPointSize: CGFloat = 15

    /// The mark drawn over the keyboard glyph.
    private enum Mark {
        /// No mark: kanata is running.
        case none
        /// Diagonal strike-through: kanata is off.
        case slash
        /// Exclamation badge: something is wrong.
        case warning
    }

    /// Template image for `status`, or nil if the SF Symbols glyph cannot be
    /// resolved (then fall back to a stock symbol name).
    static func image(for status: KanataStatus) -> NSImage? {
        let glyph: String
        let mark: Mark
        switch status {
        case .running:
            glyph = "keyboard.fill"
            mark = .none
        case .stopped:
            glyph = "keyboard"
            mark = .slash
        case .error:
            glyph = "keyboard.fill"
            mark = .warning
        case .unknown:
            glyph = "keyboard"
            mark = .none
        }
        return image(glyph: glyph, mark: mark)
    }

    /// Stock SF Symbol to use when `image(for:)` returns nil. Only
    /// `keyboard.fill`/`keyboard` are safe to assume; the old error symbol
    /// `keyboard.badge.exclamationmark` does not exist, so use a triangle.
    static func fallbackSymbol(for status: KanataStatus) -> String {
        switch status {
        case .running: return "keyboard.fill"
        case .stopped: return "keyboard"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "keyboard"
        }
    }

    // MARK: - Drawing

    private static func image(glyph: String, mark: Mark) -> NSImage? {
        guard let keyboard = NSImage(systemSymbolName: glyph, accessibilityDescription: nil)?
                .withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: glyphPointSize, weight: .regular))
        else {
            return nil
        }

        // Drawing-handler image: resolution independent, so the icon stays
        // crisp on every display and in every menu-bar size.
        let image = NSImage(size: pointSize, flipped: false) { rect in
            NSColor.black.set()
            keyboard.draw(in: NSRect(x: rect.midX - keyboard.size.width / 2,
                                     y: rect.midY - keyboard.size.height / 2,
                                     width: keyboard.size.width,
                                     height: keyboard.size.height))
            guard let context = NSGraphicsContext.current else { return false }

            switch mark {
            case .none:
                break

            case .slash:
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: rect.minX + 1.5, y: rect.minY + 1.5))
                slash.line(to: NSPoint(x: rect.maxX - 1.5, y: rect.maxY - 1.5))
                slash.lineCapStyle = .round
                // 1. Cut a gap around the slash line, so it never muddles the
                //    glyph underneath (template images are alpha-only, so
                //    destinationOut leaves a clean hole).
                context.compositingOperation = .destinationOut
                slash.lineWidth = 4.5
                slash.stroke()
                // 2. Stroke the slash itself.
                context.compositingOperation = .sourceOver
                slash.lineWidth = 1.8
                slash.stroke()

            case .warning:
                // Badge in the top-right corner: clear a ring, fill a dot, then
                // carve the exclamation out of it.
                let center = NSPoint(x: rect.maxX - 4.4, y: rect.maxY - 4.4)
                let badge = NSBezierPath()
                badge.appendArc(withCenter: center, radius: 4.6, startAngle: 0, endAngle: 360)
                context.compositingOperation = .destinationOut
                badge.lineWidth = 1.6
                badge.stroke()
                context.compositingOperation = .sourceOver
                badge.fill()

                let bar = NSBezierPath()
                bar.move(to: NSPoint(x: center.x, y: center.y + 2.4))
                bar.line(to: NSPoint(x: center.x, y: center.y - 1.2))
                bar.lineCapStyle = .round
                bar.lineWidth = 1.5
                let dot = NSBezierPath()
                dot.appendOval(in: NSRect(x: center.x - 0.8, y: center.y - 2.8,
                                          width: 1.6, height: 1.6))
                context.compositingOperation = .destinationOut
                bar.stroke()
                dot.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The menu-bar icon itself: the composed template image for the current
/// daemon status, with a stock-symbol fallback.
struct MenuBarIconView: View {
    @ObservedObject var service: KanataService

    var body: some View {
        if let image = MenuBarIcon.image(for: service.status) {
            Image(nsImage: image)
        } else {
            Image(systemName: MenuBarIcon.fallbackSymbol(for: service.status))
        }
    }
}
