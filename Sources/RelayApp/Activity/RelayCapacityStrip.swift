import SwiftUI

struct RelayCapacityStrip: View {
    let presentation: RelayCapacityPresentation

    var body: some View {
        HStack(spacing: 0) {
            if presentation.windows.isEmpty {
                RelayCapacitySlotView(window: nil)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(presentation.windows.enumerated()), id: \.element.id) {
                    index,
                    window in
                    if index > 0 {
                        Divider().overlay(RelayPalette.hairline)
                    }
                    RelayCapacitySlotView(window: window)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
