// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import PhotosUI
import SwiftUI

/// Your own profile, editable: the name, the pictures, the bio and its four
/// fields, and the switches that decide who finds you (docs/05 §5).
///
/// Only what changed is sent. A Nextcloud with an external identity backend
/// (LDAP, SAML) refuses a new name or picture with a 422; that is shown as
/// "your server manages your name and picture", never as a failure.
public struct EditProfileView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let session: AccountSession

    @State private var original: Account?
    @State private var extras = CredentialsExtras()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var managedByServer = false
    @State private var didSave = false

    // The form.
    @State private var displayName = ""
    @State private var note = ""
    @State private var fields: [Account.Field] = []
    @State private var locked = false
    @State private var discoverable = true
    @State private var indexable = true
    @State private var bot = false
    @State private var privacy: AlohaModels.Visibility = .public
    @State private var sensitive = false
    @State private var language = ""

    // Pictures picked but not yet sent.
    @State private var avatarItem: PhotosPickerItem?
    @State private var headerItem: PhotosPickerItem?
    @State private var avatarPicked: CredentialsUpdate.Picture?
    @State private var headerPicked: CredentialsUpdate.Picture?
    @State private var avatarPreview: Image?
    @State private var headerPreview: Image?

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        Form {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                }
            }

            if managedByServer {
                Section {
                    Label {
                        Text(
                            "Your server manages your name and picture. Change them in your Nextcloud settings.",
                            comment: "Profile editing note for a managed account")
                    } icon: {
                        Image(systemName: "building.2")
                    }
                    .font(.footnote)
                }
            }

            picturesSection
            aboutSection
            fieldsSection
            reachSection
            postingSection
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Edit profile", comment: "Screen title"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save", comment: "Profile editing action")
                    }
                }
                .disabled(isSaving || !hasChanges)
            }
        }
        .disabled(isLoading)
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await load() }
        .onChange(of: avatarItem) { _, item in
            Task { avatarPicked = await picture(from: item, name: "avatar") }
        }
        .onChange(of: headerItem) { _, item in
            Task { headerPicked = await picture(from: item, name: "header") }
        }
        .sensoryFeedback(.success, trigger: didSave)
    }

    // MARK: - Sections

    private var picturesSection: some View {
        Section {
            HStack(spacing: AlohaMetrics.space3) {
                Group {
                    if let avatarPreview {
                        avatarPreview.resizable().scaledToFill()
                    } else if let original {
                        AvatarView(account: original, size: 64)
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                    Text("Picture", comment: "Profile editing field")
                        .font(AlohaType.name)
                    HStack(spacing: AlohaMetrics.space3) {
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            Text("Choose…", comment: "Profile editing action")
                        }
                        if original?.avatar != nil || avatarPicked != nil {
                            Button(role: .destructive) {
                                Task { await removeAvatar() }
                            } label: {
                                Text("Remove", comment: "Profile editing action")
                            }
                        }
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, AlohaMetrics.space1)

            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                Group {
                    if let headerPreview {
                        headerPreview.resizable().scaledToFill()
                    } else if let original, let header = original.header {
                        RemoteImage(url: header)
                    } else {
                        LinearGradient(
                            colors: [
                                Monogram.colour(for: original?.acct ?? "", lightness: 0.46),
                                Monogram.colour(for: original?.acct ?? "", lightness: 0.30),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipShape(
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))

                HStack(spacing: AlohaMetrics.space3) {
                    Text("Banner", comment: "Profile editing field")
                        .font(AlohaType.name)
                    Spacer()
                    PhotosPicker(selection: $headerItem, matching: .images) {
                        Text("Choose…", comment: "Profile editing action")
                    }
                    if original?.header != nil || headerPicked != nil {
                        Button(role: .destructive) {
                            Task { await removeHeader() }
                        } label: {
                            Text("Remove", comment: "Profile editing action")
                        }
                    }
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }
            .padding(.vertical, AlohaMetrics.space1)
        } header: {
            Text("Pictures", comment: "Profile editing section")
        }
    }

    private var aboutSection: some View {
        Section {
            TextField(
                String(localized: "Display name", comment: "Profile editing field"),
                text: $displayName)
            TextField(
                String(localized: "Bio", comment: "Profile editing field"),
                text: $note, axis: .vertical
            )
            .lineLimit(3...8)
        } header: {
            Text("About you", comment: "Profile editing section")
        }
    }

    private var fieldsSection: some View {
        Section {
            ForEach(fields.indices, id: \.self) { index in
                HStack(spacing: AlohaMetrics.space2) {
                    TextField(
                        String(localized: "Label", comment: "Profile field name placeholder"),
                        text: $fields[index].name
                    )
                    .frame(maxWidth: 110)
                    TextField(
                        String(localized: "Content", comment: "Profile field value placeholder"),
                        text: $fields[index].value)
                }
            }
            .onDelete { offsets in fields.remove(atOffsets: offsets) }

            if fields.count < 4 {
                Button {
                    fields.append(Account.Field(name: "", value: ""))
                } label: {
                    Label {
                        Text("Add a field", comment: "Profile editing action")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        } header: {
            Text("Fields", comment: "Profile editing section")
        } footer: {
            Text(
                "Up to four. A link back to this profile from a site you list gets a verified mark.",
                comment: "Profile fields explanation")
        }
    }

    private var reachSection: some View {
        Section {
            Toggle(isOn: $locked) {
                Text("Approve who follows you", comment: "Profile editing switch")
            }
            Toggle(isOn: $discoverable) {
                Text("Suggest this account to others", comment: "Profile editing switch")
            }
            Toggle(isOn: $indexable) {
                Text("Let search find your public posts", comment: "Profile editing switch")
            }
            Toggle(isOn: $bot) {
                Text("This is an automated account", comment: "Profile editing switch")
            }
        } header: {
            Text("Who finds you", comment: "Profile editing section")
        }
    }

    private var postingSection: some View {
        Section {
            Picker(selection: $privacy) {
                Text("Public", comment: "Visibility").tag(Visibility.public)
                Text("Unlisted", comment: "Visibility").tag(Visibility.unlisted)
                Text("Followers only", comment: "Visibility").tag(Visibility.private)
                Text("Direct", comment: "Visibility").tag(Visibility.direct)
            } label: {
                Text("Who sees new posts", comment: "Profile editing field")
            }

            Toggle(isOn: $sensitive) {
                Text("Mark my media sensitive by default", comment: "Profile editing switch")
            }

            TextField(
                String(
                    localized: "Language, e.g. en", comment: "Profile editing field placeholder"),
                text: $language
            )
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()

            if session.capabilities.isNextcloudSocial {
                Picker(
                    selection: Binding(
                        get: { session.settings.sensitiveMediaPolicy },
                        set: { value in
                            Task {
                                await session.updateSettings { $0.sensitiveMediaPolicy = value }
                                // Nextcloud Social keeps the choice server-side too.
                                _ = try? await session.client.send(
                                    Endpoint.instance.setExpandMedia(value.rawValue))
                            }
                        })
                ) {
                    Text("Always show", comment: "Sensitive media policy").tag(
                        SensitiveMediaPolicy.showAll)
                    Text("Blur until tapped", comment: "Sensitive media policy").tag(
                        SensitiveMediaPolicy.blur)
                    Text("Don't show at all", comment: "Sensitive media policy").tag(
                        SensitiveMediaPolicy.hideAll)
                } label: {
                    Text("Media marked sensitive", comment: "Profile editing field")
                }
            }
        } header: {
            Text("Posting defaults", comment: "Profile editing section")
        } footer: {
            Text(
                "These are what a new post starts with. Every post can still be changed as you write it.",
                comment: "Posting defaults explanation")
        }
    }

    // MARK: - Data

    private var hasChanges: Bool {
        guard let original else { return false }
        return !changes(from: original).isEmpty
    }

    /// Only what differs from the profile as it was loaded.
    private func changes(from account: Account) -> CredentialsUpdate {
        var update = CredentialsUpdate()
        if displayName != account.displayName { update.displayName = displayName }
        if note != (account.source?.note ?? account.note) { update.note = note }
        let cleanFields = fields.filter { !$0.name.isEmpty || !$0.value.isEmpty }
        let originalFields = (account.source?.fields ?? account.fields).map {
            Account.Field(name: $0.name, value: $0.value)
        }
        if cleanFields != originalFields { update.fields = cleanFields }
        if locked != account.locked { update.locked = locked }
        if discoverable != account.discoverable { update.discoverable = discoverable }
        if indexable != extras.indexable { update.indexable = indexable }
        if bot != account.bot { update.bot = bot }
        if privacy != (account.source?.privacy ?? .public) { update.privacy = privacy }
        if sensitive != (account.source?.sensitive ?? false) { update.sensitive = sensitive }
        let trimmedLanguage = language.trimmingCharacters(in: .whitespaces)
        if trimmedLanguage != (account.source?.language ?? "") {
            update.language = trimmedLanguage
        }
        update.avatar = avatarPicked
        update.header = headerPicked
        return update
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let raw = try await session.client.send(Endpoint.session.verifyCredentials)
            let account = try AlohaJSON.decoder.decode(Account.self, from: raw.data)
            extras =
                (try? AlohaJSON.decoder.decode(CredentialsExtras.self, from: raw.data))
                ?? CredentialsExtras()
            apply(account)
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func apply(_ account: Account) {
        original = account
        displayName = account.displayName
        note = account.source?.note ?? account.note
        fields = (account.source?.fields ?? account.fields).map {
            Account.Field(name: $0.name, value: $0.value)
        }
        locked = account.locked
        discoverable = account.discoverable
        indexable = extras.indexable
        bot = account.bot
        privacy = account.source?.privacy ?? .public
        sensitive = account.source?.sensitive ?? false
        language = account.source?.language ?? ""
        avatarPicked = nil
        headerPicked = nil
        avatarPreview = nil
        headerPreview = nil
    }

    private func save() async {
        guard let original else { return }
        let update = changes(from: original)
        guard !update.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await session.client.decode(
                Account.self, from: Endpoint.credentials.update(update))
            if let indexable = update.indexable { extras.indexable = indexable }
            apply(saved)
            errorMessage = nil
            didSave.toggle()
            await session.refreshServerState()
        } catch let error as APIError {
            if case .unprocessable = error,
                update.displayName != nil || update.avatar != nil || update.header != nil
            {
                // The name and the pictures belong to the identity backend.
                managedByServer = true
                // Everything else still goes through.
                var rest = update
                rest.displayName = nil
                rest.avatar = nil
                rest.header = nil
                if !rest.isEmpty,
                    let saved = try? await session.client.decode(
                        Account.self, from: Endpoint.credentials.update(rest))
                {
                    apply(saved)
                    didSave.toggle()
                }
                errorMessage = nil
            } else {
                await session.handle(error)
                errorMessage = error.errorDescription
            }
        } catch {
            await session.handle(error)
            errorMessage = error.localizedDescription
        }
    }

    private func removeAvatar() async {
        avatarItem = nil
        avatarPicked = nil
        avatarPreview = nil
        guard original?.avatar != nil else { return }
        do {
            let saved = try await session.client.decode(
                Account.self, from: Endpoint.credentials.deleteAvatar)
            apply(saved)
        } catch let error as APIError {
            if case .unprocessable = error {
                managedByServer = true
            } else {
                await session.handle(error)
                errorMessage = error.errorDescription
            }
        } catch {
            await session.handle(error)
        }
    }

    private func removeHeader() async {
        headerItem = nil
        headerPicked = nil
        headerPreview = nil
        guard original?.header != nil else { return }
        do {
            let saved = try await session.client.decode(
                Account.self, from: Endpoint.credentials.deleteHeader)
            apply(saved)
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func picture(
        from item: PhotosPickerItem?, name: String
    ) async -> CredentialsUpdate.Picture? {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else {
            return nil
        }
        let type = item.supportedContentTypes.first
        let mimeType = type?.preferredMIMEType ?? "image/jpeg"
        let ext = type?.preferredFilenameExtension ?? "jpg"
        let preview = Self.image(from: data)
        if name == "avatar" { avatarPreview = preview } else { headerPreview = preview }
        return CredentialsUpdate.Picture(
            data: data, filename: "\(name).\(ext)", mimeType: mimeType)
    }

    private static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
            return UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
            return NSImage(data: data).map { Image(nsImage: $0) }
        #else
            return nil
        #endif
    }
}
