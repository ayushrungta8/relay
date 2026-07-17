import SwiftUI

struct RelayCapacityFooter: View {
    let presentation: RelayCapacityPresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDetail = false

    var body: some View {
        RelayCapacityStrip(
            presentation: presentation,
            isExpanded: showsDetail,
            toggleDetail: toggleDetail
        )
        .frame(height: 32)
        .background(RelayPalette.elevatedSurface)
        .overlay(alignment: .bottomTrailing) {
            if showsDetail {
                ScrollView {
                    RelayUsageDetailView(presentation: presentation)
                        .padding(.top, 12)
                }
                .scrollIndicators(.never)
                .frame(width: 360, height: 132)
                .background(
                    RelayPalette.shell,
                    in: .rect(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(RelayPalette.hairline, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.55), radius: 24, y: 10)
                .offset(x: -10, y: -39)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .offset(y: 6))
                )
                .zIndex(2)
            }
        }
        .animation(
            reduceMotion
                ? .linear(duration: 0.12)
                : .easeOut(duration: 0.18),
            value: showsDetail
        )
    }

    private func toggleDetail() {
        showsDetail.toggle()
    }
}
