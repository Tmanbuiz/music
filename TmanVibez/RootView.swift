import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "square.stack")
            }

            NavigationStack {
                AddMediaView()
            }
            .tabItem {
                Label("Add Media", systemImage: "plus.circle")
            }
        }
        .tint(.cyan)
    }
}
