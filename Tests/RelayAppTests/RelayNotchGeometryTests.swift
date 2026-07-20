import AppKit
import Testing
@testable import RelayApp

@MainActor
struct RelayNotchGeometryTests {
    @Test
    func builtInNotchPeekUsesAuxiliaryAreasAndScreenTop() {
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
        #expect(frame.size == CGSize(width: 468, height: 42))
    }

    @Test
    func builtInNotchCompactAddsRoomForTheBoundaryBelowTheNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let safeArea = RelayNotchSafeArea(
            topInset: 38,
            obstructionWidth: 224
        )
        let frame = RelayNotchGeometry.frame(
            for: .compact,
            screenFrame: screen,
            visibleFrame: CGRect(x: 0, y: 25, width: 1_512, height: 919),
            safeAreaInsets: .init(top: 38, left: 0, bottom: 0, right: 0),
            leftAuxiliaryArea: CGRect(
                x: 0,
                y: 944,
                width: 644,
                height: 38
            ),
            rightAuxiliaryArea: CGRect(
                x: 868,
                y: 944,
                width: 644,
                height: 38
            )
        )

        #expect(frame.maxY == screen.maxY)
        #expect(
            frame.size == CGSize(
                width: safeArea.compactCounterPanelWidth,
                height: 41
            )
        )
        #expect(frame.width < 400)
    }

    @Test
    func compactCounterOverlayWidensForABroadCameraObstruction() {
        let safeArea = RelayNotchSafeArea(
            topInset: 38,
            obstructionWidth: 480
        )
        let frame = RelayNotchGeometry.frame(
            for: .compact,
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1_440, height: 837),
            safeAreaInsets: .init(top: 38, left: 0, bottom: 0, right: 0),
            leftAuxiliaryArea: CGRect(
                x: 0,
                y: 862,
                width: 480,
                height: 38
            ),
            rightAuxiliaryArea: CGRect(
                x: 960,
                y: 862,
                width: 480,
                height: 38
            )
        )

        #expect(
            frame.size == CGSize(
                width: safeArea.compactCounterPanelWidth,
                height: 41
            )
        )
        #expect(frame.width > safeArea.compactCenterClearanceWidth)
    }

    @Test
    func notchlessOverlayExposesItsCompactHoverBoundaryAtScreenTop() {
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

        #expect(frame.maxY == screen.maxY)
        #expect(frame.size == CGSize(width: 254, height: 28))
    }

    @Test
    func notchlessPeekRetainsItsLabeledFootprint() {
        let frame = RelayNotchGeometry.frame(
            for: .peek,
            screenFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_055),
            safeAreaInsets: .init(),
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil
        )

        #expect(frame.size == CGSize(width: 400, height: 42))
    }

    @Test
    func expandedOverlayIntegratesContentWithTheCameraSafeArea() {
        let frame = RelayNotchGeometry.frame(
            for: .expanded,
            screenFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 25, width: 1_512, height: 919),
            safeAreaInsets: .init(top: 38, left: 0, bottom: 0, right: 0),
            leftAuxiliaryArea: CGRect(
                x: 0,
                y: 944,
                width: 644,
                height: 38
            ),
            rightAuxiliaryArea: CGRect(
                x: 868,
                y: 944,
                width: 644,
                height: 38
            )
        )

        #expect(frame.maxY == 982)
        #expect(frame.size == CGSize(width: 700, height: 520))
    }

    @Test
    func largeTaskContentHasNoInputToThePanelFrame() {
        let frame = RelayNotchGeometry.frame(
            for: .expanded,
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875),
            safeAreaInsets: .init(),
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil
        )

        #expect(frame.size == CGSize(width: 700, height: 520))
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
        #expect(frame.maxY == screen.maxY)
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
        #expect(frame.origin == CGPoint(x: visible.midX, y: screen.maxY))
    }
}
