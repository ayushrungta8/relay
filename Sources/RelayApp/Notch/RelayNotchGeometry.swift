import AppKit

enum RelayNotchGeometry {
    static func frame(
        for presentation: RelayPanelPresentation,
        contentHeight: Double? = nil,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaInsets: NSEdgeInsets,
        leftAuxiliaryArea: CGRect?,
        rightAuxiliaryArea: CGRect?
    ) -> CGRect {
        let notchWidth = notchWidth(
            leftAuxiliaryArea: leftAuxiliaryArea,
            rightAuxiliaryArea: rightAuxiliaryArea
        )
        let hasNotch = notchWidth != nil
        let topAnchor = hasNotch ? screenFrame.maxY : visibleFrame.maxY

        guard presentation != .hidden else {
            return CGRect(
                origin: CGPoint(x: visibleFrame.midX, y: topAnchor),
                size: .zero
            )
        }

        let width = min(
            targetWidth(
                for: presentation,
                notchWidth: notchWidth,
                visibleWidth: visibleFrame.width
            ),
            visibleFrame.width
        )
        let maximumHeight = min(
            visibleFrame.height * 0.7,
            topAnchor - visibleFrame.minY
        )
        let height = min(
            targetHeight(
                for: presentation,
                topInset: hasNotch ? safeAreaInsets.top : 0,
                contentHeight: contentHeight
            ),
            maximumHeight
        )
        let centeredX = screenFrame.midX - width / 2
        let originX = min(
            max(centeredX, visibleFrame.minX),
            visibleFrame.maxX - width
        )

        return CGRect(
            x: originX,
            y: topAnchor - height,
            width: width,
            height: height
        )
    }

    private static func notchWidth(
        leftAuxiliaryArea: CGRect?,
        rightAuxiliaryArea: CGRect?
    ) -> Double? {
        guard
            let leftAuxiliaryArea,
            let rightAuxiliaryArea
        else {
            return nil
        }

        let width = rightAuxiliaryArea.minX - leftAuxiliaryArea.maxX
        return width > 0 ? width : nil
    }

    private static func targetWidth(
        for presentation: RelayPanelPresentation,
        notchWidth: Double?,
        visibleWidth: Double
    ) -> Double {
        let contentWidth: Double = switch presentation {
        case .hidden:
            0
        case .peek:
            min(320, visibleWidth)
        case .compact:
            min(560, visibleWidth)
        case .expanded:
            min(680, visibleWidth)
        }

        return max(contentWidth, notchWidth ?? 0)
    }

    private static func targetHeight(
        for presentation: RelayPanelPresentation,
        topInset: Double,
        contentHeight: Double?
    ) -> Double {
        if let contentHeight,
           contentHeight.isFinite,
           contentHeight > 0
        {
            return topInset + contentHeight
        }
        return switch presentation {
        case .hidden:
            0
        case .peek:
            topInset + 52
        case .compact:
            topInset + 180
        case .expanded:
            topInset + 520
        }
    }
}
