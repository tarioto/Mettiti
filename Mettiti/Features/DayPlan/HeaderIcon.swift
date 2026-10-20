import SwiftUI

/// A main-screen header button's icon. Plain black or white so the theme's accent tint doesn't
/// color it.
struct HeaderIcon: View {
    let systemName: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(colorScheme == .dark ? .white : .black)
            .frame(width: 32, height: 32)
    }
}

extension View {
    /// The circular glass look shared by the main-screen header's buttons and menus.
    func headerIconButtonStyle() -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(.circle)
    }
}
