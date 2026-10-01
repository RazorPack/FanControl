import AppKit
import SwiftUI

@main
struct FanControlApp: App {
    @StateObject private var store = FanStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("FanControl", id: "main") {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    store.start()
                    appDelegate.store = store
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Вентилятор") {
                Button("Авто") { store.select(.auto) }
                Button("Тихий") { store.select(.quiet) }
                Button("Баланс") { store.select(.balanced) }
                Button("Нагрузка") { store.select(.performance) }
                Button("Максимум") { store.select(.full) }
                Divider()
                Button("Разрешить управление…") { store.installHelper() }
                    .keyboardShortcut("e", modifiers: [.command])
            }
        }

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(store.snapshot.displayRPM) об/мин")
                    .font(.headline.monospacedDigit())
                if let cpu = store.snapshot.cpuTemp {
                    Text(String(format: "CPU %.0f°C", cpu))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Button("Авто") { store.select(.auto) }
                Button("Тихий") { store.select(.quiet) }
                Button("Баланс") { store.select(.balanced) }
                Button("Нагрузка") { store.select(.performance) }
                Button("Максимум") { store.select(.full) }
                Divider()
                Button("Открыть FanControl") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "FanControl" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                Button("Выйти") {
                    store.stop()
                    NSApp.terminate(nil)
                }
            }
            .padding(8)
            .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: FanStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            store?.stop()
        }
    }
}
