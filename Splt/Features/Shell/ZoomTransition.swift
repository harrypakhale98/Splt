import SwiftUI

extension EnvironmentValues {
    /// The namespace that links a list row to the screen it opens with a zoom transition.
    @Entry var zoomNamespace: Namespace.ID?
}

extension Route {
    /// Group and friend screens zoom out of their row. Everything else slides in as usual.
    var zoomSourceID: Route? {
        switch self {
        case .group, .friend: self
        default: nil
        }
    }
}

extension View {
    /// Marks a list row as the place a route's screen zooms out of.
    func zoomSource(for route: Route) -> some View {
        modifier(ZoomSource(route: route))
    }
}

private struct ZoomSource: ViewModifier {
    let route: Route
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: route, in: namespace)
        } else {
            content
        }
    }
}

struct ZoomDestination: ViewModifier {
    let route: Route
    @Environment(\.zoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let namespace, let source = route.zoomSourceID, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: source, in: namespace))
        } else {
            content
        }
    }
}
