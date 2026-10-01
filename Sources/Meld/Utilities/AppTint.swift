import SwiftUI

extension EnvironmentValues {
    /// The app-wide injectable accent tint color.
    @Entry var appTint: Color = PackageResourceLookup.brandAccent
}

extension View {
    /// Sets the app-wide accent tint for this view hierarchy.
    func appTint(_ color: Color) -> some View {
        self.environment(\.appTint, color)
    }
}
