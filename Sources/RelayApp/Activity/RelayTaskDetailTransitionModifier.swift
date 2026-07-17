import SwiftUI

struct RelayTaskDetailTransitionModifier: ViewModifier {
    let opacity: Double
    let verticalOffset: CGFloat
    let blurRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: verticalOffset)
            .blur(radius: blurRadius)
    }
}

extension AnyTransition {
    static var relayTaskDetail: AnyTransition {
        .modifier(
            active: RelayTaskDetailTransitionModifier(
                opacity: 0,
                verticalOffset: 5,
                blurRadius: 3
            ),
            identity: RelayTaskDetailTransitionModifier(
                opacity: 1,
                verticalOffset: 0,
                blurRadius: 0
            )
        )
    }
}
