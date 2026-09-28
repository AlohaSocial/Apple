// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// Attaching a file that is already on the Nextcloud, so a 200 MB video never
/// travels to the phone and back (docs/07 §6).
///
/// **Not a file browser.** Browsing needs WebDAV credentials that the Social
/// OAuth token does not grant — that is open question §3 item 4. What this does
/// instead is take a path, remember the ones that worked, and report the
/// server's own 422 plainly when a path is wrong.
public struct NextcloudFilePicker: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let onPick: (String) -> Void

    @State private var path = ""
    @State private var recents: [String] = RecentNextcloudPaths.load()

    public init(onPick: @escaping (String) -> Void) {
        self.onPick = onPick
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        text: $path,
                        prompt: Text(verbatim: "Photos/holiday.jpg")
                    ) {
                        Text("Path in your files", comment: "Nextcloud file picker field")
                    }
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { pick() }

                    Button {
                        pick()
                    } label: {
                        Text("Attach", comment: "Nextcloud file picker action")
                    }
                    .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text(
                        "Relative to your own files. The file is copied, so moving or deleting it later won't empty your post.",
                        comment: "Nextcloud file picker explanation")
                }

                if !recents.isEmpty {
                    Section {
                        ForEach(recents, id: \.self) { recent in
                            Button {
                                path = recent
                                pick()
                            } label: {
                                Label {
                                    Text(recent).lineLimit(1).truncationMode(.head)
                                } icon: {
                                    Image(systemName: "doc")
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text("Recent", comment: "Nextcloud file picker section")
                            Spacer()
                            Button {
                                RecentNextcloudPaths.clear()
                                recents = []
                            } label: {
                                Text("Clear", comment: "Nextcloud file picker action")
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Attach from Nextcloud", comment: "Screen title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Sheet action")
                    }
                }
            }
        }
    }

    private func pick() {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        recents = RecentNextcloudPaths.remember(trimmed)
        onPick(trimmed)
        dismiss()
    }
}

enum RecentNextcloudPaths {
    private static let key = "aloha.recentNextcloudPaths"
    private static let limit = 8

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func remember(_ value: String) -> [String] {
        var history = load().filter { $0 != value }
        history.insert(value, at: 0)
        history = Array(history.prefix(limit))
        UserDefaults.standard.set(history, forKey: key)
        return history
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
