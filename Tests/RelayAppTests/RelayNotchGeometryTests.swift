import AppKit
import Testing
@testable import RelayApp

@MainActor
struct RelayNotchGeometryTests {
    @Test
    func builtInNotchUsesAuxiliaryAreasAndScreenTop() {
        let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let visible = CGRect(x: 0, y: 25, width: 1_512, height: 919)
        let leftAuxiliary = CGRect(
            x: 0,
            y: 944,
            width: 644,
            height: 38
        )
        let rightAuxiliary = CGRect(
            x: 868,
            y: 944,
            width: 644,
            height: 38
        )

        let frame = RelayNotchGeometry.frame(
            for: .peek,
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaInsets: NSEdgeInsets(
                top: 38,
                left: 0,
                bottom: 0,
                right: 0
            ),
            leftAuxiliaryArea: leftAuxiliary,
            rightAuxiliaryArea: rightAuxiliary
        )

        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == screen.maxY)
        #expect(frame.width >= rightAuxiliary.minX - leftAuxiliary.maxX)
        #expect(frame.height > 38)
    }

    @Test
    func noNotchDisplayFallsBackBelowTheMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let visible = CGRect(x: 0, y: 0, width: 1_920, height: 1_055)

        let frame = RelayNotchGeometry.frame(
            for: .compact,
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaInsets: .init(),
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil
        )

        #expect(frame.midX == visible.midX)
        #expect(frame.maxY == visible.maxY)
        #expect(visible.contains(frame))
    }

    @Test
    func measuredContentHeightDrivesThePanelAndStillClampsToTheDisplay() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 875)

        let compact = RelayNotchGeometry.frame(
            for: .compact,
            contentHeight: 132,
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaInsets: .init(),
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil
        )
        let oversized = RelayNotchGeometry.frame(
            for: .expanded,
            contentHeight: 2_000,
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaInsets: .init(),
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil
        )

        #expect(compact.height == 132)
        #expect(oversized.height == visible.height * 0.7)
    }

    @Test
    func externalDisplayFrameClampsToItsOffsetVisibleArea() {
        let screen = CGRect(x: -1_280, y: 120, width: 1_280, height: 720)
        let visible = CGRect(
            x: -1_280,
            y: 160,
            width: 1_040,
            height: 640
        )

        let frame = RelayNotchGeometry.frame(
            for: .expanded,
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaInsets: .init(),
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil
        )

        #expect(frame.minX >= visible.minX)
        #expect(frame.maxX <= visible.maxX)
        #expect(frame.minY >= visible.minY)
        #expect(frame.maxY <= visible.maxY)
        #expect(frame.height <= visible.height * 0.7)
    }

    @Test
    func hiddenPresentationProducesAnEmptyTopCenteredFrame() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 875)

        let frame = RelayNotchGeometry.frame(
            for: .hidden,
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaInsets: .init(),
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil
        )

        #expect(frame.size == .zero)
        #expect(frame.origin == CGPoint(x: visible.midX, y: visible.maxY))
    }
}
