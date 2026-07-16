enum RelayComposerPhase: Equatable {
    case idle
    case listening
    case sending
    case failed(String)
}
