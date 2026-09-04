enum FocusDirection {
    case forward
    case backward

    var offset: Int {
        switch self {
        case .forward:
            return 1
        case .backward:
            return -1
        }
    }
}
