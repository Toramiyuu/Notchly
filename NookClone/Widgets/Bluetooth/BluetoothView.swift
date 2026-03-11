import SwiftUI

struct BluetoothView: View {

    @ObservedObject private var manager = BluetoothManager.shared

    var body: some View {
        Group {
            if manager.devices.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(manager.devices) { device in
                            BluetoothRow(device: device)
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
        }
        .onAppear { manager.startIfNeeded() }
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "bluetooth")
                .foregroundStyle(.white.opacity(0.25))
            Text("No paired devices")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct BluetoothRow: View {
    let device: BluetoothDevice
    private let manager = BluetoothManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.sfSymbol)
                .font(.system(size: 16))
                .foregroundStyle(device.isConnected ? .white : .white.opacity(0.3))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(device.isConnected ? .white.opacity(0.9) : .white.opacity(0.4))
                    .lineLimit(1)

                if let battery = device.batteryPercent {
                    HStack(spacing: 3) {
                        Image(systemName: batterySymbol(battery))
                            .font(.system(size: 9))
                            .foregroundStyle(batteryColor(battery))
                        Text("\(battery)%")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            Spacer()

            Button {
                if device.isConnected { manager.disconnect(device) }
                else { manager.connect(device) }
            } label: {
                Text(device.isConnected ? "Disconnect" : "Connect")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(device.isConnected ? 0.12 : 0.06),
                                in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white.opacity(device.isConnected ? 0.8 : 0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func batterySymbol(_ pct: Int) -> String {
        switch pct {
        case 75...: return "battery.100"
        case 50...: return "battery.75"
        case 25...: return "battery.50"
        case 10...: return "battery.25"
        default:    return "battery.0"
        }
    }

    private func batteryColor(_ pct: Int) -> Color {
        pct <= 15 ? .red : pct <= 30 ? .yellow : .green
    }
}
