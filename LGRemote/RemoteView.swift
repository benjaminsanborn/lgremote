import SwiftUI

struct RemoteView: View {
    @EnvironmentObject private var viewModel: RemoteViewModel
    @State private var showNumberPad = false

    var body: some View {
        VStack(spacing: 14) {
            header
                .padding(.bottom, 6)
            if viewModel.state == .pairing {
                pairingBanner
            }
            topRow
            Spacer(minLength: 12)
            rockers
            directionPad
                .padding(.top, 8)
            Spacer(minLength: 12)
            navigationRow
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [Color(red: 0.11, green: 0.11, blue: 0.13),
                                    Color(red: 0.04, green: 0.04, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .sheet(isPresented: $showNumberPad) {
            NumberPadView()
                .presentationDetents([.height(360)])
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Menu {
                ForEach(viewModel.tvs) { tv in
                    Button {
                        viewModel.select(tv)
                    } label: {
                        if tv.id == viewModel.selectedTV?.id {
                            Label(tv.name, systemImage: "checkmark")
                        } else {
                            Text(tv.name)
                        }
                    }
                }
                Divider()
                Button {
                    viewModel.showSetup = true
                } label: {
                    Label("Manage TVs…", systemImage: "gearshape")
                }
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.selectedTV?.name ?? "No TV")
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
            }

            Spacer()

            Button {
                Haptics.tap()
                if viewModel.state == .connected {
                    viewModel.connect()
                } else {
                    viewModel.showPicker = true
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(viewModel.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .connected: return .green
        case .connecting, .pairing: return .orange
        case .disconnected: return .red
        }
    }

    private var pairingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Check the TV and accept the connection request.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
    }

    // MARK: Top row — power, inputs, apps, numbers, mute

    private var topRow: some View {
        HStack(spacing: 16) {
            RemoteKey(icon: "power", size: 54, tint: .white, fill: Color(red: 0.85, green: 0.15, blue: 0.15)) {
                Haptics.heavy()
                viewModel.powerToggle()
            }

            Menu {
                if viewModel.inputs.isEmpty {
                    Text(viewModel.state == .connected ? "No inputs found" : "Connect to load inputs")
                } else {
                    ForEach(viewModel.inputs) { input in
                        Button(input.label) {
                            viewModel.run { try await $0.switchInput(id: input.id) }
                        }
                    }
                }
            } label: {
                keyLabel(icon: "tv.and.hifispeaker.fill", size: 54)
            }

            Menu {
                if viewModel.apps.isEmpty {
                    Text(viewModel.state == .connected ? "No apps found" : "Connect to load apps")
                } else {
                    ForEach(viewModel.apps) { app in
                        Button(app.title) {
                            viewModel.run { try await $0.launchApp(id: app.id) }
                        }
                    }
                }
            } label: {
                keyLabel(icon: "square.grid.2x2.fill", size: 54)
            }

            Button {
                Haptics.tap()
                showNumberPad = true
            } label: {
                keyLabel(icon: "number", size: 54)
            }
            .buttonStyle(KeyButtonStyle())

            RemoteKey(icon: "speaker.slash.fill", size: 54) {
                viewModel.run { try await $0.toggleMute() }
            }
        }
    }

    // MARK: D-pad

    private var directionPad: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.06))
                .overlay(Circle().stroke(.white.opacity(0.06), lineWidth: 1))

            VStack {
                dpadArrow("chevron.up", button: "UP")
                Spacer()
                dpadArrow("chevron.down", button: "DOWN")
            }
            .padding(.vertical, 14)

            HStack {
                dpadArrow("chevron.left", button: "LEFT")
                Spacer()
                dpadArrow("chevron.right", button: "RIGHT")
            }
            .padding(.horizontal, 14)

            Button {
                Haptics.heavy()
                viewModel.button("ENTER")
            } label: {
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 88, height: 88)
                    .overlay(
                        Text("OK")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    )
            }
            .buttonStyle(KeyButtonStyle())
        }
        .frame(width: 250, height: 250)
    }

    private func dpadArrow(_ icon: String, button: String) -> some View {
        Button {
            Haptics.tap()
            viewModel.button(button)
        } label: {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 60, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyButtonStyle())
    }

    // MARK: Navigation row

    private var navigationRow: some View {
        HStack(spacing: 24) {
            RemoteKey(icon: "arrow.uturn.backward", size: 66) { viewModel.button("BACK") }
            RemoteKey(icon: "house.fill", size: 66) { viewModel.button("HOME") }
            RemoteKey(icon: "slider.horizontal.3", size: 66) { viewModel.button("MENU") }
            RemoteKey(icon: "xmark", size: 66) { viewModel.button("EXIT") }
        }
    }

    // MARK: Volume / channel rockers

    private var rockers: some View {
        HStack(spacing: 26) {
            Rocker(label: "VOL", topIcon: "plus", bottomIcon: "minus") {
                viewModel.run { try await $0.volumeUp() }
            } bottomAction: {
                viewModel.run { try await $0.volumeDown() }
            }

            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    RemoteKey(icon: "info", size: 52) { viewModel.button("INFO") }
                    RemoteKey(icon: "captions.bubble", size: 52) { viewModel.button("CC") }
                }
                HStack(spacing: 14) {
                    RemoteKey(icon: "play.fill", size: 52) { viewModel.run { try await $0.play() } }
                    RemoteKey(icon: "pause.fill", size: 52) { viewModel.run { try await $0.pause() } }
                }
                HStack(spacing: 14) {
                    RemoteKey(icon: "backward.fill", size: 52) { viewModel.run { try await $0.rewind() } }
                    RemoteKey(icon: "forward.fill", size: 52) { viewModel.run { try await $0.fastForward() } }
                }
            }

            Rocker(label: "CH", topIcon: "chevron.up", bottomIcon: "chevron.down") {
                viewModel.run { try await $0.channelUp() }
            } bottomAction: {
                viewModel.run { try await $0.channelDown() }
            }
        }
    }

    private func keyLabel(icon: String, size: CGFloat = 56) -> some View {
        Circle()
            .fill(.white.opacity(0.08))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Components

struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct RemoteKey: View {
    let icon: String
    var size: CGFloat = 56
    var tint: Color = .white
    var fill: Color = .white.opacity(0.08)
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Circle()
                .fill(fill)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: size * 0.32, weight: .semibold))
                        .foregroundStyle(tint)
                )
        }
        .buttonStyle(KeyButtonStyle())
    }
}

struct Rocker: View {
    let label: String
    let topIcon: String
    let bottomIcon: String
    let topAction: () -> Void
    let bottomAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            rockerButton(icon: topIcon, action: topAction)
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            rockerButton(icon: bottomIcon, action: bottomAction)
        }
        .frame(width: 74)
        .background(
            RoundedRectangle(cornerRadius: 37)
                .fill(.white.opacity(0.08))
        )
    }

    private func rockerButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyButtonStyle())
    }
}

// MARK: - Number pad

struct NumberPadView: View {
    @EnvironmentObject private var viewModel: RemoteViewModel
    @Environment(\.dismiss) private var dismiss

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(row, id: \.self) { digit in
                        digitKey(digit)
                    }
                }
            }
            HStack(spacing: 24) {
                digitKey("DASH", title: "–")
                digitKey("0", title: "0")
                RemoteKey(icon: "arrow.uturn.backward", size: 62) { viewModel.button("BACK") }
            }
            Spacer()
        }
        .padding()
    }

    private func digitKey(_ button: String, title: String? = nil) -> some View {
        Button {
            Haptics.tap()
            viewModel.button(button)
        } label: {
            Circle()
                .fill(.white.opacity(0.1))
                .frame(width: 62, height: 62)
                .overlay(
                    Text(title ?? button)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                )
        }
        .buttonStyle(KeyButtonStyle())
    }
}
