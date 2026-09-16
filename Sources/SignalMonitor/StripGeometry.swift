import Foundation

enum StripGeometry {
    static let reflowDuration: TimeInterval = 0.20
    static let tileWidth: CGFloat = 74
    static let tileHeight: CGFloat = 93
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 6

    static func offset(index: Int, columns: Int) -> CGPoint {
        let columns = max(columns, 1)
        return CGPoint(x: CGFloat(index % columns) * (tileWidth + spacing),
                       y: CGFloat(index / columns) * (tileHeight + spacing))
    }

    static func anchoredFrame(size: CGSize, from frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    static func size(count: Int, columns: Int) -> CGSize {
        let count = max(count, 1)
        let columns = min(count, max(columns, 1))
        let rows = (count + columns - 1) / columns
        return CGSize(width: CGFloat(columns) * (tileWidth + spacing) - spacing + 2 * padding,
                      height: CGFloat(rows) * (tileHeight + spacing) - spacing + 2 * padding)
    }

    // Preserve content size: an unusually small display must not crop the grid.
    static func constrained(_ frame: CGRect, to visible: CGRect) -> CGRect {
        guard !visible.isEmpty else { return frame }
        var result = frame
        result.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
        result.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
        return result
    }

    static func resisted(_ frame: CGRect, to visible: CGRect) -> CGRect {
        let target = constrained(frame, to: visible)
        var result = frame
        // Bounded rubber band: initially soft, progressively firmer further out.
        func rubberBand(_ distance: CGFloat) -> CGFloat {
            let magnitude = abs(distance)
            let offset = 64 * (1 - 1 / (1 + magnitude * 0.35 / 64))
            return distance < 0 ? -offset : offset
        }
        result.origin.x = target.minX + rubberBand(frame.minX - target.minX)
        result.origin.y = target.minY + rubberBand(frame.minY - target.minY)
        return result
    }
}
