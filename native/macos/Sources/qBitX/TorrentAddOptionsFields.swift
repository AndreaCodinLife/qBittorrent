import SwiftUI

struct TorrentAddOptionsFields: View {
    @Binding var draft: TorrentAddOptionsDraft
    let store: TorrentStore

    var body: some View {
        Section("Torrent management") {
            Picker("Mode", selection: $draft.managementMode) {
                Text("Default").tag(DefaultableBool.default)
                Text("Manual").tag(DefaultableBool.no)
                Text("Automatic").tag(DefaultableBool.yes)
            }
            .pickerStyle(.segmented)

            if draft.managementMode == .no {
                HStack {
                    TextField("Save location", text: $draft.savePath)
                        .textFieldStyle(.roundedBorder)
                    ServerPathBrowserButton(store: store, path: $draft.savePath, kind: .directory)
                        .accessibilityLabel("Choose save location")
                }
            } else {
                Text("qBittorrent chooses the save location from its default and category rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Use another path for incomplete torrents", selection: $draft.useDownloadPath) {
                ForEach(DefaultableBool.allCases) { choice in
                    Text(LocalizedStringKey(choice.label)).tag(choice)
                }
            }
            .disabled(draft.managementMode != .no)

            if draft.managementMode == .no && draft.useDownloadPath == .yes {
                HStack {
                    TextField("Incomplete location", text: $draft.downloadPath)
                        .textFieldStyle(.roundedBorder)
                    ServerPathBrowserButton(store: store, path: $draft.downloadPath, kind: .directory)
                        .accessibilityLabel("Choose incomplete location")
                }
            }
        }

        Section("Organization") {
            TextField("Category", text: $draft.category)
            TextField("Tags, separated by commas", text: $draft.tags)
        }

        Section("When a torrent is added") {
            Picker("Content layout", selection: layoutSelection) {
                Text("Default").tag("")
                Text("Original").tag("Original")
                Text("Create subfolder").tag("Subfolder")
                Text("Don't create subfolder").tag("NoSubfolder")
            }

            Toggle("Seed mode", isOn: $draft.seedMode)

            Picker("Start torrent", selection: $draft.startTorrent) {
                ForEach(DefaultableBool.allCases) { choice in
                    Text(LocalizedStringKey(choice.label)).tag(choice)
                }
            }

            Picker("Stop condition", selection: stopConditionSelection) {
                Text("Default").tag("")
                Text("None").tag("None")
                Text("Metadata received").tag("MetadataReceived")
                Text("Files checked").tag("FilesChecked")
            }

            Picker("Add to top of queue", selection: $draft.addToQueueTop) {
                ForEach(DefaultableBool.allCases) { choice in
                    Text(LocalizedStringKey(choice.label)).tag(choice)
                }
            }
        }

        Section("Torrent share limits") {
            shareLimitRow("Ratio", mode: $draft.ratioMode, value: $draft.ratioValue, placeholder: "1.0")
            shareLimitRow("Seeding time (minutes)", mode: $draft.seedingTimeMode, value: $draft.seedingTimeValue, placeholder: "1440")
            shareLimitRow("Inactive seeding time (minutes)", mode: $draft.inactiveTimeMode, value: $draft.inactiveTimeValue, placeholder: "1440")

            Picker("Mode", selection: $draft.shareLimitsMode) {
                Text("Default").tag("Default")
                Text("Match any limit").tag("MatchAny")
                Text("Match all limits").tag("MatchAll")
            }

            Picker("Action when a limit is reached", selection: $draft.shareLimitAction) {
                Text("Default").tag("Default")
                Text("Stop torrent").tag("Stop")
                Text("Remove torrent").tag("Remove")
                Text("Remove torrent and its content").tag("RemoveWithContent")
                Text("Enable super seeding").tag("EnableSuperSeeding")
            }
        }
    }

    private var layoutSelection: Binding<String> {
        Binding(
            get: { draft.contentLayout ?? "" },
            set: { draft.contentLayout = $0.isEmpty ? nil : $0 }
        )
    }

    private var stopConditionSelection: Binding<String> {
        Binding(
            get: { draft.stopCondition ?? "" },
            set: { draft.stopCondition = $0.isEmpty ? nil : $0 }
        )
    }

    private func shareLimitRow(_ title: String, mode: Binding<ShareValueMode>, value: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
            Spacer(minLength: 24)
            Picker(title, selection: mode) {
                ForEach(ShareValueMode.allCases) { choice in
                    Text(LocalizedStringKey(choice.label)).tag(choice)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            if mode.wrappedValue == .setValue {
                TextField(placeholder, text: value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }
        }
    }
}
