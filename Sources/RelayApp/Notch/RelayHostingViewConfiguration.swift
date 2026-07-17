import SwiftUI

enum RelayHostingViewConfiguration {
    static func apply<Content: View>(to host: NSHostingView<Content>) {
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.autoresizingMask = [.width, .height]
    }
}
