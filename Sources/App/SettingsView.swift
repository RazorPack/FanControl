import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var selectedLanguage = AppLanguage.system.rawValue
    @AppStorage("launchMinimized") private var launchMinimized = false
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Picker(AppLanguage.localized("Язык приложения"), selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            Text(AppLanguage.localized("Язык применяется сразу ко всему интерфейсу."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(AppLanguage.localized("Запускать в свернутом режиме"), isOn: $launchMinimized)
            Text(AppLanguage.localized("При запуске главное окно будет скрыто; приложение останется доступно в строке меню."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(AppLanguage.localized("Запускать при входе в систему"), isOn: Binding(
                get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
                set: { setLaunchAtLogin($0) }
            ))

            if loginItemStatus == .requiresApproval {
                Button(AppLanguage.localized("Открыть настройки объектов входа")) {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else if loginItemStatus == .notFound {
                Text(AppLanguage.localized("Не удалось определить приложение для автозапуска."))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 430)
        .onChange(of: selectedLanguage) { _, newValue in
            if let language = AppLanguage(rawValue: newValue) {
                AppLanguage.apply(language)
            }
        }
        .onAppear(perform: refreshLoginItemStatus)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItemStatus()
        } catch {
            refreshLoginItemStatus()
            loginItemError = error.localizedDescription
        }
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }
}
