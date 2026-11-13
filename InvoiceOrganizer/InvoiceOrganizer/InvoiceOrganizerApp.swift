import SwiftUI

@main
struct InvoiceOrganizerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 560)
        }
        Window("合并预览", id: "preview") {
            PreviewWindowView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}
