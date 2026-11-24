import SwiftUI

@main struct SeekMoonApp: App {
    var body: some Scene {
        WindowGroup { ConsoleScreen().ignoresSafeArea() }
    }
}

private struct ConsoleScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ConsoleController { ConsoleController() }
    func updateUIViewController(_ controller: ConsoleController, context: Context) {}
}
