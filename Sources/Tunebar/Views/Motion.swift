import SwiftUI

/// The app's two motions, used everywhere so things move alike.
extension Animation {
    /// Things changing place or size: the card growing into Now Playing, Up Next and panels opening,
    /// pages changing. Fast and snappy, without overshoot, so the pieces land together.
    static let move = Animation.snappy(duration: 0.3)
    /// Small changes in place: hover controls, highlights, toasts, a new track's details.
    static let quick = Animation.snappy(duration: 0.18)
}
