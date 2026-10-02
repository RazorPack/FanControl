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
                    appDelegate.configureMainWindow(launchMinimized: UserDefaults.standard.bool(forKey: "launchMinimized"))
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
            Text("\(store.snapshot.displayRPM) \(AppLanguage.localized("RPM"))")
            if let cpu = store.snapshot.cpuTemp {
                Text("CPU \(String(format: "%.0f°C", cpu))")
            }
            Divider()
            ForEach(ControlMode.allCases.filter { $0 != .custom }) { mode in
                Button {
                    store.select(mode)
                } label: {
                    if store.mode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(verbatim: mode.title)
                    }
                }
            }
            Divider()
            Button(AppLanguage.localized("Свернуть в строку меню")) {
                    appDelegate.hideMainWindow()
            }
            Button(AppLanguage.localized("Открыть MacFanControl")) {
                appDelegate.showMainWindow()
            }
            Button(AppLanguage.localized("Выйти")) {
                store.stop()
                NSApp.terminate(nil)
            }
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var store: FanStore?
    private var didConfigureMainWindow = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func configureMainWindow(launchMinimized: Bool) {
        guard !didConfigureMainWindow else { return }
        didConfigureMainWindow = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.mainWindow?.delegate = self
            if launchMinimized {
                self.hideMainWindow()
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isMainWindow(sender) else { return true }
        hideMainWindow()
        return false
    }

    func windowWillMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, isMainWindow(window) else { return }
        hideMainWindow()
    }

    func hideMainWindow() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.hide(nil)
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showMainWindow()
        }
        return true
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first(where: isMainWindow)
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "main" || window.title == "MacFanControl"
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            store?.stop()
        }
    }
}
