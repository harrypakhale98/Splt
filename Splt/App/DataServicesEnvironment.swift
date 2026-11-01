import SwiftUI

extension EnvironmentValues {
    /// The repositories and stores the app runs on. Nil in a bare preview, where views show an empty state.
    @Entry var dataServices: DataServices?
}
