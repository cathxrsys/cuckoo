import AppKit

/// Процент: «5.1%», «43%» (одна цифра после точки, нули отбрасываются).
func fmtPercent(_ p: Double) -> String {
    let r = (p * 10).rounded() / 10
    return r == r.rounded() ? "\(Int(r))%" : String(format: "%.1f%%", r)
}

/// Картинка для меню-бара. Шаблонная (чёрное + прозрачность) — система сама красит под светлый/тёмный бар.
enum StatusImage {
    static let height: CGFloat = 22
    static let iconSize: CGFloat = 14

    /// claude: (5 часов, неделя), codex: неделя. Строки уже отформатированы.
    static func limits(claude: (String, String), codex: String) -> NSImage {
        let small = attrs(size: 9)
        let single = attrs(size: 11)
        let top = NSAttributedString(string: claude.0, attributes: small)
        let bottom = NSAttributedString(string: claude.1, attributes: small)
        let cx = NSAttributedString(string: codex, attributes: single)

        let colW = ceil(max(top.size().width, bottom.size().width))
        let gap: CGFloat = 6, between: CGFloat = 9
        let width = clawdWidth + gap + colW + between + iconSize + gap + ceil(cx.size().width)

        return draw(width: width) {
            var x: CGFloat = 0
            drawClawd(x: x)
            x += clawdWidth + gap
            // две строки: сверху 5 часов, снизу неделя (выравнивание вправо)
            top.draw(at: NSPoint(x: x + colW - top.size().width, y: height / 2 - 0.5))
            bottom.draw(at: NSPoint(x: x + colW - bottom.size().width, y: height / 2 - bottom.size().height + 1.5))
            x += colW + between
            drawCodex(in: NSRect(x: x, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
            x += iconSize + gap
            cx.draw(at: NSPoint(x: x, y: (height - cx.size().height) / 2))
        }
    }

    /// Пауза/статус: просто текст.
    static func text(_ s: String) -> NSImage {
        let a = NSAttributedString(string: s, attributes: attrs(size: 11))
        return draw(width: ceil(a.size().width)) {
            a.draw(at: NSPoint(x: 0, y: (height - a.size().height) / 2))
        }
    }

    private static func attrs(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.black]
    }

    private static func draw(width: CGFloat, _ body: @escaping () -> Void) -> NSImage {
        let img = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in body(); return true }
        img.isTemplate = true
        return img
    }

    // MARK: Клод-жук из баннера Claude Code (символы-квадранты → пиксели)

    private static let clawdArt = [" ▐▛███▜▌", "▝▜█████▛▘", "  ▘▘ ▝▝"]
    /// квадрант: (верх-лево, верх-право, низ-лево, низ-право)
    private static let quads: [Character: (Bool, Bool, Bool, Bool)] = [
        " ": (false, false, false, false), "█": (true, true, true, true),
        "▐": (false, true, false, true), "▌": (true, false, true, false),
        "▛": (true, true, true, false), "▜": (true, true, false, true),
        "▝": (false, true, false, false), "▘": (true, false, false, false),
    ]
    private static let clawdCols = 18, clawdRows = 6
    private static let px: CGFloat = 0.85                       // ширина «пикселя»
    static var clawdWidth: CGFloat { CGFloat(clawdCols) * px }

    static func drawClawd(x: CGFloat) {
        let ph = px * 2                                         // ячейка терминала вытянута по вертикали
        let top = (height + CGFloat(clawdRows) * ph) / 2
        let path = NSBezierPath()
        for (row, line) in clawdArt.enumerated() {
            for (col, ch) in line.enumerated() {
                guard let q = quads[ch] else { continue }
                let cells = [(q.0, 0, 0), (q.1, 1, 0), (q.2, 0, 1), (q.3, 1, 1)]
                for (on, dx, dy) in cells where on {
                    let cx = x + CGFloat(col * 2 + dx) * px
                    let cy = top - CGFloat(row * 2 + dy + 1) * ph
                    path.appendRect(NSRect(x: cx, y: cy, width: px, height: ph))
                }
            }
        }
        NSColor.black.setFill()
        path.fill()
    }

    // MARK: Codex: облако с «>_»

    static func drawCodex(in r: NSRect) {
        let s = r.width
        let c = NSPoint(x: r.midX, y: r.midY)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - s * 0.33, y: c.y - s * 0.33, width: s * 0.66, height: s * 0.66)).fill()
        let lobes = 7
        for i in 0..<lobes {
            let a = CGFloat(i) / CGFloat(lobes) * 2 * .pi + 0.35
            let lr = s * 0.19
            let o = NSPoint(x: c.x + cos(a) * s * 0.3, y: c.y + sin(a) * s * 0.3)
            NSBezierPath(ovalIn: NSRect(x: o.x - lr, y: o.y - lr, width: lr * 2, height: lr * 2)).fill()
        }
        // вырезаем «>_»
        NSGraphicsContext.current?.compositingOperation = .clear
        let p = NSBezierPath()
        p.lineWidth = s * 0.115
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.move(to: NSPoint(x: c.x - s * 0.19, y: c.y + s * 0.15))
        p.line(to: NSPoint(x: c.x - s * 0.06, y: c.y))
        p.line(to: NSPoint(x: c.x - s * 0.19, y: c.y - s * 0.15))
        p.move(to: NSPoint(x: c.x + s * 0.04, y: c.y - s * 0.15))
        p.line(to: NSPoint(x: c.x + s * 0.21, y: c.y - s * 0.15))
        p.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}
