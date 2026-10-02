import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: FanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            gauge
            modes
            slider
            temperatures
            helperBar
            safetyNote
        }
        .padding(22)
        .frame(width: 440)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacFanControl")
                    .font(.title2.weight(.semibold))
                Text(machineLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusChip
        }
    }

    private var machineLine: String {
        let model = store.snapshot.model.isEmpty ? String(localized: "Mac") : store.snapshot.model
        let chip = store.snapshot.chip.isEmpty ? String(localized: "Apple Silicon") : store.snapshot.chip
        return "\(chip) · \(model)"
    }

    private var statusChip: some View {
        let auto = store.mode == .auto
        return Text(auto ? "macOS" : "ручной")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(auto ? Color.green.opacity(0.2) : Color.orange.opacity(0.22), in: Capsule())
            .foregroundStyle(auto ? Color.green : Color.orange)
    }

    private var gauge: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: store.snapshot.percent)
                    .stroke(
                        AngularGradient(colors: [.cyan, .blue, .orange, .red], center: .center),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: store.snapshot.percent)
                VStack(spacing: 2) {
                    Text("\(store.snapshot.displayRPM)")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("RPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 168, height: 168)

            VStack(alignment: .leading, spacing: 10) {
                metric("Цель", "\(Int(store.snapshot.targetRPM.rounded()))")
                metric("Диапазон", "\(Int(store.snapshot.minRPM))–\(Int(store.snapshot.maxRPM))")
                metric("Режим SMC", modeLabel(store.snapshot.mode))
                metric("Тепло", thermalLabel)
            }
            Spacer()
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
    }

    private var thermalLabel: LocalizedStringKey {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "норма"
        case .fair: return "тепло"
        case .serious: return "жарко"
        case .critical: return "критично"
        @unknown default: return "—"
        }
    }

    private func modeLabel(_ mode: Int) -> LocalizedStringKey {
        switch mode {
        case 0: return "авто (0)"
        case 1: return "ручной (1)"
        case 3: return "система (3)"
        default: return "\(mode)"
        }
    }

    private var modes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Профили")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(ControlMode.allCases.filter { $0 != .custom }) { mode in
                    Button(mode.title) { store.select(mode) }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            store.mode == mode ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(store.mode == mode ? Color.accentColor : .clear, lineWidth: 1)
                        )
                }
            }
        }
    }

    private var slider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Целевые обороты")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(Int(store.customRPM.rounded()))")
                        .font(.caption.monospacedDigit())
                    Text("RPM")
                        .font(.caption)
                }
            }
            Slider(
                value: Binding(
                    get: { store.customRPM },
                    set: { store.setCustomRPM($0) }
                ),
                in: store.snapshot.minRPM...max(store.snapshot.maxRPM, store.snapshot.minRPM + 1),
                step: 50
            )
            .disabled(!store.helperInstalled && store.mode != .auto)
        }
    }

    private var temperatures: some View {
        HStack(spacing: 8) {
            tempCard("CPU", store.snapshot.cpuTemp, .orange)
            tempCard("GPU", store.snapshot.gpuTemp, .purple)
            tempCard("NAND", store.snapshot.nandTemp, .indigo)
            tempCard("Wi‑Fi", store.snapshot.wifiTemp, .teal)
        }
    }

    private func tempCard(_ title: String, _ value: Double?, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.0f°", $0) } ?? "—")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(colorFor(value, color))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func colorFor(_ value: Double?, _ fallback: Color) -> Color {
        guard let value else { return fallback }
        if value >= 90 { return .red }
        if value >= 78 { return .orange }
        return fallback
    }

    private var helperBar: some View {
        Group {
            if store.snapshot.helper {
                Label("Фоновый сервис активен · \(store.lastApplied)", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.helperInstalled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Сервис установлен, но сейчас не отвечает. Запустите его снова паролем администратора.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Перезапустить сервис") { store.installHelper() }
                        .disabled(store.installing)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Чтение датчиков уже работает. Для ручного управления вентилятором нужен одноразовый пароль администратора — SMC принимает запись оборотов только от root.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        store.installHelper()
                    } label: {
                        Text(store.installing ? "Установка…" : "Разрешить управление вентилятором")
                    }
                    .disabled(store.installing)
                    .keyboardShortcut("e", modifiers: [.command])
                }
            }
        }
    }

    private var safetyNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = store.helperError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Не удерживайте минимум при высокой температуре. При CPU ≥ 95 °C приложение поднимает обороты и при выходе возвращает управление macOS.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject private var store: FanStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: store.mode == .auto ? "fanblades" : "fanblades.fill")
            Text("\(store.snapshot.displayRPM)")
                .monospacedDigit()
        }
    }
}
