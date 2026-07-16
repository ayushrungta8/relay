import SwiftUI

struct RelayLoadingView: View {
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 11) {
                    Circle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: index.isMultiple(of: 2) ? 210 : 250)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(width: 128, height: 8)
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 58)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading recent Codex tasks")
    }
}
