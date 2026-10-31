import CoreGraphics
import Testing
@testable import DisplaySplitCore

struct ColumnSplitTests {
    @Test(arguments: [
        ("1:2:1", ColumnSplit(left: 1, center: 2, right: 1)),
        (" 1 : 2.5 : 1 ", ColumnSplit(left: 1, center: 2.5, right: 1)),
        ("1:3:2", ColumnSplit(left: 1, center: 3, right: 2)),
    ])
    func parsesThreePositiveShares(text: String, expected: ColumnSplit?) {
        #expect(ColumnSplit(text) == expected)
    }

    @Test(arguments: ["", "1:2", "1:2:1:1", "1::1", "0:2:1", "-1:2:1", "a:b:c", "inf:1:1", "nan:1:1", "1,2,1"])
    func rejectsMalformedOrNonPositive(text: String) {
        #expect(ColumnSplit(text) == nil)
    }

    @Test(arguments: ["1:2:1", "1:2.5:1", "0.5:3:1"])
    func descriptionRoundTrips(text: String) throws {
        let split = try #require(ColumnSplit(text))
        #expect(split.description == text)
        #expect(ColumnSplit(split.description) == split)
    }
}

struct ColumnLayoutTests {
    static let wide = CGSize(width: 2560, height: 1440)

    @Test(arguments: ["1:2:1", "1:3:2", "1:1:1", "0.3:5:0.7"], [
        CGRect(x: 0, y: 0, width: 2560, height: 1410),
        CGRect(x: -2561, y: 300, width: 2561, height: 1410), // display left of and below primary, odd width
    ])
    func columnsTileTheVisibleFrameExactly(split: String, frame: CGRect) throws {
        let layout = ColumnLayout(visibleFrame: frame, screenSize: Self.wide, split: try #require(ColumnSplit(split)))
        #expect(layout.left.minX == frame.minX)
        #expect(layout.left.maxX == layout.center.minX)
        #expect(layout.center.maxX == layout.right.minX)
        #expect(layout.right.maxX == frame.maxX)
        for column in Column.allCases {
            let rect = layout.frame(for: column)
            #expect(rect.minY == frame.minY && rect.height == frame.height)
            #expect(rect.width == rect.width.rounded())
        }
    }

    @Test func widthsFollowProportions() {
        let visible = CGRect(x: 0, y: 0, width: 2560, height: 1410)
        let layout = ColumnLayout(visibleFrame: visible, screenSize: Self.wide, split: ColumnSplit(left: 1, center: 3, right: 2)!)
        // 2560 / 6 = 426.67 → 427, 2 × 426.67 = 853.33 → 853, center takes the remainder.
        #expect(layout.left == CGRect(x: 0, y: 0, width: 427, height: 1410))
        #expect(layout.center == CGRect(x: 427, y: 0, width: 1280, height: 1410))
        #expect(layout.right == CGRect(x: 1707, y: 0, width: 853, height: 1410))
    }

    @Test(arguments: [
        CGSize(width: 1728, height: 1117), // MacBook Pro 16"
        CGSize(width: 2560, height: 1600), // exactly 16:10
        CGSize(width: 1440, height: 2560), // portrait
    ])
    func screensNoWiderThan16x10AreNotSplit(screen: CGSize) {
        let visible = CGRect(x: 0, y: 0, width: screen.width, height: screen.height - 40)
        let layout = ColumnLayout(visibleFrame: visible, screenSize: screen, split: .default)
        #expect(layout.center == visible)
        #expect(layout.left.minX == visible.minX && layout.left.maxX == layout.right.minX)
        #expect(layout.right.maxX == visible.maxX)
    }

    @Test func screenJustWiderThan16x10IsSplit() {
        let screen = CGSize(width: 2561, height: 1600)
        let visible = CGRect(origin: .zero, size: screen)
        #expect(ColumnLayout(visibleFrame: visible, screenSize: screen, split: .default).center.width == 1281)
    }
}

struct CoordinateTests {
    @Test func flipConvertsCocoaToAccessibility() {
        // Visible frame above a 70pt Dock, below a 25pt menu bar on a 1440pt-tall primary display.
        let cocoa = CGRect(x: 100, y: 70, width: 800, height: 1345)
        #expect(flipVertically(cocoa, primaryScreenHeight: 1440) == CGRect(x: 100, y: 25, width: 800, height: 1345))
    }

    @Test func flipIsItsOwnInverse() {
        let rect = CGRect(x: -1920, y: 1500, width: 1920, height: 1080) // display above the primary
        #expect(flipVertically(flipVertically(rect, primaryScreenHeight: 1440), primaryScreenHeight: 1440) == rect)
    }

    @Test func centeredSplitsSlackAndPinsOverflow() {
        let target = CGRect(x: 218, y: 25, width: 2124, height: 1415)
        #expect(centered(CGSize(width: 2117, height: 1408), in: target)
            == CGRect(x: 221, y: 28, width: 2117, height: 1408))
        // Window with a minimum size larger than the column stays at the column's origin.
        #expect(centered(CGSize(width: 2400, height: 1415), in: target).origin == target.origin)
    }
}
