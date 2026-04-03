import SwiftUI

struct WeatherView: View {

    @ObservedObject private var manager  = WeatherManager.shared
    @ObservedObject private var settings = WeatherSettings.shared

    var body: some View {
        if let error = manager.errorMessage {
            errorView(error)
        } else if manager.isLoading && manager.temperatureC == nil {
            loadingView
        } else {
            mainContent
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon
            Image(systemName: manager.weatherSymbol)
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
                // Temperature
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(displayTemp)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(settings.useFahrenheit ? "°F" : "°C")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                // Condition
                Text(manager.weatherDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                // High/low
                if manager.dailyHighC != nil || manager.dailyLowC != nil {
                    HStack(spacing: 4) {
                        if let h = manager.dailyHighC {
                            Text("H: \(tempString(h))")
                        }
                        if let l = manager.dailyLowC {
                            Text("L: \(tempString(l))")
                        }
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                }

                // City + wind
                HStack(spacing: 6) {
                    if !manager.cityName.isEmpty {
                        Label(manager.cityName, systemImage: "location.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    if let wind = manager.windspeedKph {
                        Label(String(format: "%.0f km/h", wind), systemImage: "wind")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var displayTemp: String {
        guard let c = manager.temperatureC else { return "--" }
        return String(format: "%.0f", converted(c))
    }

    private func tempString(_ c: Double) -> String {
        String(format: "%.0f°", converted(c))
    }

    private func converted(_ c: Double) -> Double {
        settings.useFahrenheit ? c * 9 / 5 + 32 : c
    }

    private func errorView(_ message: String) -> some View {
        let isLocationError = message.lowercased().contains("location") ||
                              message.lowercased().contains("denied")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow.opacity(0.7))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            if isLocationError {
                Button {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
                    )
                } label: {
                    Text("Open Location Settings →")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Fetching weather…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
