import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var selectedLanguage = AppLanguage.system.rawValue

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
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 390)
        .onChange(of: selectedLanguage) { _, newValue in
            if let language = AppLanguage(rawValue: newValue) {
                AppLanguage.apply(language)
            }
        }
    }
}
