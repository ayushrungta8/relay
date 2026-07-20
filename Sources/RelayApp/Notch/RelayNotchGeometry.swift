import AppKit

enum RelayNotchGeometry {
    static func frame(
        for presentation: RelayPanelPresentation,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaInsets: NSEdgeInsets,
        leftAuxiliaryArea: CGRect?,
        rightAuxiliaryArea: CGRect?
    ) -> CGRect {
        let topAnchor = screenFrame.maxY
        let obstructionWidth = obstructionWidth(
            leftAuxiliaryArea: leftAuxiliaryArea,
            rightAuxiliaryArea: rightAuxiliaryArea
        )
        let hasCameraHousing = safeAreaInsets.top > 0

        guard presentation != .hidden else {
            return CGRect(
                origin: CGPoint(x: visibleFrame.midX, y: topAnchor),
                size: .zero
            )
        }

        let requiredWidth = switch presentation {
        case .peek, .compact:
            if hasCameraHousing {
                max(
                    targetWidth(for: presentation),
                    RelayNotchSafeArea(
                        topInset: safeAreaInsets.top,
                        obstructionWidth: obstructionWidth
                    ).minimumCompactPanelWidth
                )
            } else {
                targetWidth(for: presentation)
            }
        case .hidden, .expanded:
            targetWidth(for: presentation)
        }
        let width = min(requiredWidth, visibleFrame.width)
        let maximumHeight = min(
            visibleFrame.height * 0.7,
            topAnchor - visibleFrame.minY
        )
        let contentHeight = targetHeight(for: presentation)
        let cameraClearance = max(0, safeAreaInsets.top)
        let requiredHeight = max(contentHeight, cameraClearance)
        let height = min(requiredHeight, maximumHeight)
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

    private static func obstructionWidth(
        leftAuxiliaryArea: CGRect?,
        rightAuxiliaryArea: CGRect?
    ) -> Double {
        guard let leftAuxiliaryArea, let rightAuxiliaryArea else { return 0 }
        return Double(
            max(0, rightAuxiliaryArea.minX - leftAuxiliaryArea.maxX)
        )
    }

    private static func targetWidth(
        for presentation: RelayPanelPresentation
    ) -> Double {
        switch presentation {
        case .hidden:
            0
        case .peek, .compact:
            400
        case .expanded:
            700
        }
    }

    private static func targetHeight(
        for presentation: RelayPanelPresentation
    ) -> Double {
        switch presentation {
        case .hidden:
            0
        case .peek, .compact:
            42
        case .expanded:
            520
        }
    }
}
