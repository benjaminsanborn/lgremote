import SwiftUI

/// Launch screen: shows every saved TV with live power status. Tapping a TV
/// wakes it if needed and connects; the app switches to the remote as soon as
/// a connection is established.
struct TVPickerView: View {
    @EnvironmentObject private var viewModel: RemoteViewModel

    private let statusTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "tv")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Choose a TV")
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                ForEach(viewModel.tvs) { tv in
                    tvRow(tv)
                }
            }
            .padding(.horizontal, 24)

            Button {
                Haptics.tap()
                viewModel.showSetup = true
            } label: {
                Label("Manage TVs…", systemImage: "gearshape")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Spacer()

            if viewModel.state == .connected {
                Button("Open Remote") {
                    viewModel.showPicker = false
                }
                .font(.headline)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.11, green: 0.11, blue: 0.13),
                                    Color(red: 0.04, green: 0.04, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onAppear { viewModel.refreshStatuses() }
        .onReceive(statusTimer) { _ in viewModel.refreshStatuses() }
    }

    private func tvRow(_ tv: TVDevice) -> some View {
        let isSelected = tv.id == viewModel.selectedTV?.id
        let isBusy = isSelected && (viewModel.state == .connecting || viewModel.state == .pairing)
        return Button {
            Haptics.heavy()
            viewModel.wakeAndConnect(tv)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor(for: tv, isSelected: isSelected))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tv.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(statusText(for: tv, isSelected: isSelected, isBusy: isBusy))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(isSelected ? 0.12 : 0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(KeyButtonStyle())
        .disabled(isBusy)
    }

    private func statusColor(for tv: TVDevice, isSelected: Bool) -> Color {
        if isSelected && viewModel.state == .connected { return .green }
        switch viewModel.awake[tv.id] {
        case true: return .green
        case false: return .red
        default: return .gray
        }
    }

    private func statusText(for tv: TVDevice, isSelected: Bool, isBusy: Bool) -> String {
        if isSelected {
            switch viewModel.state {
            case .connected: return "Connected"
            case .pairing: return "Pairing — accept the prompt on the TV"
            case .connecting: return viewModel.awake[tv.id] == false ? "Waking up…" : "Connecting…"
            case .disconnected: break
            }
        }
        if isBusy { return "Connecting…" }
        switch viewModel.awake[tv.id] {
        case true: return "Ready — tap to connect"
        case false: return "Off — tap to turn on"
        default: return "Checking status…"
        }
    }
}
