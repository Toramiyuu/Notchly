import SwiftUI

struct NewsSettingsView: View {

    @ObservedObject private var settings = NewsSettings.shared

    var body: some View {
        Form {
            Section("News Source") {
                Picker("Source", selection: $settings.selectedSourceID) {
                    ForEach(NewsSource.presets) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.selectedSourceID) { _, _ in
                    NewsManager.shared.fetch()
                }
            }
            Section("Display") {
                HStack {
                    Text("Max headlines")
                    Spacer()
                    Stepper("\(settings.maxItems)", value: $settings.maxItems, in: 5...25, step: 5)
                }
            }
        }
        .formStyle(.grouped)
    }
}
