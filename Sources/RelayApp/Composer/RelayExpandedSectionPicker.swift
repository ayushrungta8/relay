import SwiftUI

struct RelayExpandedSectionPicker: View {
    @Binding var selection: RelayExpandedSection

    var body: some View {
        Picker("Relay section", selection: $selection) {
            ForEach(RelayExpandedSection.allCases) { section in
                Text(section.rawValue)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 270)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(RelayPalette.shell)
    }
}
