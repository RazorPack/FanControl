import AppKit
import SwiftUI

@main
struct MacFanControlApp: App {
    @StateObject private var store = FanStore()
    @AppStorage("appLanguage") private var selectedLanguage = AppLanguage.system.rawValue
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppLanguage.apply(AppLanguage.current)
    }

    var body: some Scene {
        Window("MacFanControl", id: "main") {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    store.start()
                    appDelegate.store = store
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    if let language = AppLanguage(rawValue: newValue) {
                        AppLanguage.apply(language)
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(AppLanguage.localized("Вентилятор")) {
                Button(AppLanguage.localized("Авто")) { store.select(.auto) }
                Button(AppLanguage.localized("Тихий")) { store.select(.quiet) }
                Button(AppLanguage.localized("Баланс")) { store.select(.balanced) }
                Button(AppLanguage.localized("Нагрузка")) { store.select(.performance) }
                Button(AppLanguage.localized("Максимум")) { store.select(.full) }
                Divider()
                Button(AppLanguage.localized("Разрешить управление…")) { store.installHelper() }
                    .keyboardShortcut("e", modifiers: [.command])
            }
        }

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("\(store.snapshot.displayRPM)")
                        .font(.headline.monospacedDigit())
                    Text(AppLanguage.localized("RPM"))
                        .font(.headline)
                }
                if let cpu = store.snapshot.cpuTemp {
                    HStack(spacing: 4) {
                        Text("CPU")
                        Text(String(format: "%.0f°C", cpu))
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Button(AppLanguage.localized("Авто")) { store.select(.auto) }
                Button(AppLanguage.localized("Тихий")) { store.select(.quiet) }
                Button(AppLanguage.localized("Баланс")) { store.select(.balanced) }
                Button(AppLanguage.localized("Нагрузка")) { store.select(.performance) }
                Button(AppLanguage.localized("Максимум")) { store.select(.full) }
                Divider()
                Button(AppLanguage.localized("Свернуть в строку меню")) {
                    NSApp.hide(nil)
                }
                Button(AppLanguage.localized("Открыть MacFanControl")) {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "MacFanControl" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                Button(AppLanguage.localized("Выйти")) {
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "MacFanControl" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            store?.stop()
        }
    }
}
