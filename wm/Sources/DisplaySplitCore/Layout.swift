import CoreGraphics
import Foundation

public enum Column: CaseIterable, Sendable {
    case left, center, right
}

/// Relative widths of the left, center and right columns, e.g. 1:2:1.
public struct ColumnSplit: Equatable, Sendable, CustomStringConvertible {
    public let left: Double
    public let center: Double
    public let right: Double

    public static let `default` = ColumnSplit(left: 1, center: 2, right: 1)!

    /// `nil` unless every share is a finite number greater than zero.
    public init?(left: Double, center: Double, right: Double) {
        guard [left, center, right].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        self.left = left
        self.center = center
        self.right = right
    }

    /// Parses "left:center:right", e.g. "1:2:1" or "1 : 2.5 : 1".
    public init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            .map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3, let left = parts[0], let center = parts[1], let right = parts[2] else { return nil }
        self.init(left: left, center: center, right: right)
    }

    public var description: String {
        [left, center, right].map { String(format: "%g", $0) }.joined(separator: ":")
    }
}

/// Splits a screen's visible frame into left | center | right columns that tile it exactly.
/// Works in any coordinate space with x growing rightward; only x and width are split.
public struct ColumnLayout: Equatable, Sendable {
    public let left: CGRect
    public let center: CGRect
    public let right: CGRect

    /// Screens no wider than 16:10 (laptops, 16:10 and portrait monitors) are not split.
    public static let minimumSplitAspect: CGFloat = 16.0 / 10.0

    /// `screenSize` is the full display size, used only to decide whether the screen is wide
    /// enough to split. On narrower screens the center fills the visible frame and the sides
    /// are its halves.
    public init(visibleFrame v: CGRect, screenSize: CGSize, split: ColumnSplit) {
        guard screenSize.width / screenSize.height > Self.minimumSplitAspect else {
            let half = (v.width / 2).rounded(.down)
            center = v
            left = CGRect(x: v.minX, y: v.minY, width: half, height: v.height)
            right = CGRect(x: v.minX + half, y: v.minY, width: v.width - half, height: v.height)
            return
        }
        let total = split.left + split.center + split.right
        let leftWidth = (v.width * split.left / total).rounded()
        let rightWidth = (v.width * split.right / total).rounded()
        left = CGRect(x: v.minX, y: v.minY, width: leftWidth, height: v.height)
        center = CGRect(x: left.maxX, y: v.minY, width: v.width - leftWidth - rightWidth, height: v.height)
        right = CGRect(x: center.maxX, y: v.minY, width: rightWidth, height: v.height)
    }

    public func frame(for column: Column) -> CGRect {
        switch column {
        case .left: left
        case .center: center
        case .right: right
        }
    }
}

/// Converts between Cocoa screen coordinates (origin bottom-left of the primary display, y up)
/// and Accessibility/Quartz coordinates (origin top-left of the primary display, y down).
/// The conversion is its own inverse.
public func flipVertically(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
}

/// Where to put a window of `size` inside `target`: centered on any axis where it is smaller
/// (e.g. terminals snapping to character cells), pinned to the target's origin where it is not.
public func centered(_ size: CGSize, in target: CGRect) -> CGRect {
    let x = target.minX + max(0, ((target.width - size.width) / 2).rounded(.down))
    let y = target.minY + max(0, ((target.height - size.height) / 2).rounded(.down))
    return CGRect(origin: CGPoint(x: x, y: y), size: size)
}
