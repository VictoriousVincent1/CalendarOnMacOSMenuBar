import SwiftUI

@main
struct MenuCalApp: App {
    @StateObject private var model = CalendarModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(model.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
