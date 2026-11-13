import SwiftUI
import UIKit

/// The animation vocabulary of the app. Use these instead of ad hoc values, and the modifiers
/// below so people who turn on Reduce Motion get a quiet cross fade instead of movement.
enum Motion {
    /// Layout changes: switching a segment or filter, showing or hiding a section, a list growing.
    static let smooth = Animation.smooth
    /// Things under your finger: the split bar and its method, the orbit's focus, snapping back after a pinch.
    static let snappy = Animation.snappy
    /// Presses, selections and toggles of a single control.
    static let quick = Animation.snappy(duration: 0.2)
    /// Things arriving on screen, such as a banner or the number pad rising from the bottom.
    static let settle = Animation.spring(duration: 0.45, bounce: 0.1)
    /// A slow reveal for a moment worth watching, such as a recap or the orbit.
    static let reveal = Animation.smooth(duration: 0.9)

    /// The animation to use, or nil to skip it when motion is reduced.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Runs `changes` with an animation, or without one when Reduce Motion is on.
    @MainActor
    static func perform(_ animation: Animation = smooth, _ changes: () -> Void) {
        if UIAccessibility.isReduceMotionEnabled {
            changes()
        } else {
            withAnimation(animation, changes)
        }
    }

    /// A transition that only fades when motion is reduced.
    static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

extension Binding {
    /// Animates changes made through this binding, unless Reduce Motion is on. Use it on pickers
    /// and menus whose choice reshapes the screen, so they move the way a button doing the same would.
    @MainActor
    func motion(_ animation: Animation = Motion.smooth) -> Binding<Value> {
        self.animation(UIAccessibility.isReduceMotionEnabled ? nil : animation)
    }
}

extension View {
    /// Animates changes of `value`, unless Reduce Motion is on.
    func motion<V: Equatable>(_ animation: Animation = Motion.smooth, value: V) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }

    /// A transition that becomes a plain fade when Reduce Motion is on.
    func motionTransition(_ transition: AnyTransition) -> some View {
        modifier(MotionTransition(transition: transition))
    }
}

private struct MotionAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}

private struct MotionTransition: ViewModifier {
    let transition: AnyTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(Motion.transition(transition, reduceMotion: reduceMotion))
    }
}
