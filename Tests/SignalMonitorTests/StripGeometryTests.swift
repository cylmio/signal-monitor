import XCTest
@testable import SignalMonitor

final class StripGeometryTests: XCTestCase {
    func testFortyEightTasksFitSixRowsOfEight() {
        XCTAssertEqual(StripGeometry.size(count: 48, columns: 8), CGSize(width: 660, height: 610))
        XCTAssertEqual(StripGeometry.offset(index: 47, columns: 8), CGPoint(x: 574, y: 505))
    }

    func testElevenTaskReflowKeepsFirstThreeCardsAndTopLeftFixed() {
        for index in 0..<3 {
            XCTAssertEqual(StripGeometry.offset(index: index, columns: 3),
                           StripGeometry.offset(index: index, columns: 4))
        }
        let old = CGRect(origin: CGPoint(x: 700, y: 100), size: StripGeometry.size(count: 11, columns: 3))
        let desired = StripGeometry.anchoredFrame(size: StripGeometry.size(count: 11, columns: 4), from: old)
        XCTAssertEqual(desired.minX, old.minX)
        XCTAssertEqual(desired.maxY, old.maxY)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let settled = StripGeometry.constrained(desired, to: screen)
        XCTAssertEqual(settled.maxX, screen.maxX)
        XCTAssertEqual(settled.maxY, desired.maxY)
        XCTAssertEqual(settled.size, desired.size)
    }

    func testGridIncludesIncompleteRowAndPadding() {
        XCTAssertEqual(StripGeometry.size(count: 7, columns: 3), CGSize(width: 250, height: 307))
        XCTAssertEqual(StripGeometry.size(count: 0, columns: 0), CGSize(width: 86, height: 105))
    }

    func testNegativeDisplayCoordinatesAndCornerSettlement() {
        let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let proposed = CGRect(x: -1500, y: 680, width: 250, height: 105)
        let settled = StripGeometry.constrained(proposed, to: screen)
        XCTAssertEqual(settled, CGRect(x: -1440, y: 595, width: 250, height: 105))
        let resisted = StripGeometry.resisted(proposed, to: screen)
        XCTAssertGreaterThan(resisted.minX, proposed.minX)
        XCTAssertLessThan(resisted.minX, settled.minX)
        XCTAssertGreaterThan(resisted.minY, settled.minY)
        XCTAssertLessThan(resisted.minY, proposed.minY)
        XCTAssertEqual(StripGeometry.constrained(resisted, to: screen), settled)
    }

    func testInteriorIsUnchangedAndOvershootIsBounded() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let inside = CGRect(x: 100, y: 200, width: 250, height: 105)
        XCTAssertEqual(StripGeometry.resisted(inside, to: screen), inside)
        let far = inside.offsetBy(dx: 10000, dy: -10000)
        let resisted = StripGeometry.resisted(far, to: screen)
        XCTAssertLessThan(resisted.maxX - screen.maxX, 64)
        XCTAssertLessThan(screen.minY - resisted.minY, 64)
        XCTAssertEqual(resisted.size, inside.size)
    }
}
