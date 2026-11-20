// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaNetwork
import AlohaUI
import AppKit
import ServiceManagement
import SwiftUI

/// The way into the app from outside any window: the Dock menu, the
/// Services menu and the menu bar extra.
///
/// Each can be used with every window closed, where there is no shell to
/// post a notification to. SwiftUI's `openWindow` works without one, but it
/// is only handed to views; the first window or the menu bar extra to appear
/// leaves it here, and AppKit's callers use it from then on.
@MainActor
enum MacWindows {
    static var openWindow: OpenWindowAction?

    /// A new post in a compose window of its own (docs/09 §2).
    static func compose(draftText: String = "") {
        activate()
        if let openWindow {
            openWindow(value: ComposeWindowRequest(draftText: draftText))
        } else {
            // Before any view has appeared, which a service request at
            // launch can be: the main window's shell takes the request when
            // it starts, and opens the compose window itself.
            NotificationCenter.default.post(
                name: RouteResolver.composeRequested, object: nil,
                userInfo: ["draft": draftText])
        }
    }

    /// A destination in a main window — the one in front, or a new one when
    /// every window is closed.
    ///
    /// The route is left where a shell takes it (`IntentNavigation`): a
    /// running one at once, a new one as it becomes active. Still there
    /// after the announcement means no shell took it, so there is no window
    /// to show it in yet.
    static func open(_ route: Route) {
        activate()
        IntentNavigation.enqueue(route)
        if AppGroup.defaults.data(forKey: AppGroup.pendingRouteKey) != nil {
            openWindow?(id: AlohaWindow.main)
        }
    }

    /// Whatever asked, from the Dock or the menu bar, the app may be behind
    /// forty other windows: it comes forward first, so the result is seen.
    static func activate() {
        NSApplication.shared.activate()
    }
}

extension View {
    /// Leaves this scene's `openWindow` for AppKit's callers (`MacWindows`).
    func providesWindowOpener() -> some View {
        modifier(WindowOpenerProvider())
    }
}

private struct WindowOpenerProvider: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear { MacWindows.openWindow = openWindow }
    }
}

/// How the Mac's windows are drawn and laid out, as their own pane in the
/// Settings window. Every switch here is an option the app works without.
struct MacWindowSettings: View {
    static let isTranslucentKey = MacOptions.translucentWindowKey

    @AppStorage(MacOptions.translucentWindowKey) private var isTranslucent = true
    @AppStorage(MacOptions.columnWidthKey) private var columnWidth: Double = 0
    @AppStorage(MacOptions.contextColumnKey) private var showsContextColumn = false
    @AppStorage(MacOptions.deckKey) private var showsDeck = false
    @AppStorage(MacOptions.linkPreviewsKey) private var loadsLinkPreviews = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isTranslucent) {
                    Text("Translucent window", comment: "Mac setting")
                    Text(
                        "The desktop shows through around what you are reading. Posts stay on a solid ground.",
                        comment: "Mac setting detail")
                }
                Picker(selection: columnChoice) {
                    Text("Narrow", comment: "Reading column width").tag(MacOptions.narrowColumn)
                    Text("Medium", comment: "Reading column width").tag(MacOptions.mediumColumn)
                    Text("Wide", comment: "Reading column width").tag(MacOptions.wideColumn)
                    if !isPreset {
                        Text("Custom", comment: "Reading column width").tag(columnWidth)
                    }
                } label: {
                    Text("Reading column", comment: "Mac setting")
                    Text(
                        "You can also drag the column's right edge.",
                        comment: "Mac setting detail")
                }
            } header: {
                Text("Window", comment: "Mac Settings pane")
            }

            Section {
                Toggle(isOn: $showsContextColumn) {
                    Text("Trends beside the feed", comment: "Mac setting")
                    Text(
                        "Trending hashtags, suggested people and your lists in a column of their own. The toolbar has a button to show and hide it.",
                        comment: "Mac setting detail")
                }
                Toggle(isOn: $showsDeck) {
                    Text("Several columns", comment: "Mac setting")
                    Text(
                        "My Feed, Activities and Local side by side, each scrolling by itself.",
                        comment: "Mac setting detail")
                }
            } header: {
                Text("Layout", comment: "Mac Settings section")
            }

            Section {
                Toggle(isOn: $loadsLinkPreviews) {
                    Text("Load pictures for links", comment: "Mac setting")
                    Text(
                        "A link without a picture fetches one from the page it leads to. That site learns that somebody looked.",
                        comment: "Mac setting detail")
                }
            } header: {
                Text("Links", comment: "Mac Settings section")
            }

            Section {
                Picker(selection: $dockIcon) {
                    ForEach(AlohaIconVariant.allCases) { variant in
                        Text(verbatim: variant.displayName).tag(variant.rawValue)
                    }
                } label: {
                    Text("Dock icon", comment: "Mac setting")
                    Text(
                        "Shown while Aloha Social is running; the Finder keeps the app's own.",
                        comment: "Mac setting detail")
                }
                .onChange(of: dockIcon) { _, _ in MacDockIcon.apply() }
            } header: {
                Text("Icon", comment: "Mac Settings section")
            }
        }
        .formStyle(.grouped)
    }

    @AppStorage(MacDockIcon.key) private var dockIcon = AlohaIconVariant.aloha.rawValue

    private var isPreset: Bool {
        [MacOptions.narrowColumn, MacOptions.mediumColumn, MacOptions.wideColumn]
            .contains(effectiveWidth)
    }

    private var effectiveWidth: Double {
        columnWidth > 0 ? columnWidth : MacOptions.mediumColumn
    }

    private var columnChoice: Binding<Double> {
        Binding(get: { effectiveWidth }, set: { columnWidth = $0 })
    }
}

/// The app's alternate icons, on the Mac: the Dock icon of the running app.
///
/// macOS has no alternate app icons — the icon in the Finder is the
/// bundle's, and stays it — but a running app may draw its own Dock tile.
/// The alternates are square pictures made for iOS, so each is drawn into
/// the Mac's rounded tile with the margin a Mac icon keeps around itself.
@MainActor
enum MacDockIcon {
    static let key = "aloha.mac.dockIcon"

    /// Sets the Dock icon to the one chosen, or back to the bundle's.
    static func apply() {
        let chosen =
            UserDefaults.standard.string(forKey: key)
            .flatMap(AlohaIconVariant.init(rawValue:)) ?? .aloha
        guard chosen != .aloha,
            let source = NSImage(named: "DockIcon-\(chosen.rawValue.capitalized)")
        else {
            NSApplication.shared.applicationIconImage = nil
            return
        }
        NSApplication.shared.applicationIconImage = tile(from: source)
    }

    private static func tile(from source: NSImage) -> NSImage {
        let side: CGFloat = 512
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let inset = side * 0.098
            let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
            let radius = rect.width * 0.2237
            NSGraphicsContext.current?.imageInterpolation = .high
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            source.draw(in: rect)
            return true
        }
    }
}

/// Login: whether the app opens when the person logs in, and what closing
/// the last window does, as their own pane in the Settings window.
///
/// The Mac gets no push from the server, so notifications arrive only while
/// the app runs (docs/09 §2). Closing the last window leaves it running for
/// that reason; opening at login is the other half.
struct MacStartupSettings: View {
    @State private var status = SMAppService.mainApp.status
    @State private var failure: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { status == .enabled }, set: { setOpensAtLogin($0) })) {
                    Text("Open at login", comment: "Mac setting")
                    Text(
                        "Aloha Social starts when you log in, so notifications arrive without opening it first.",
                        comment: "Mac setting detail")
                }
                if status == .requiresApproval {
                    HStack {
                        Text(
                            "Allow Aloha Social in Login Items to finish.",
                            comment: "Mac setting: login item waiting for approval")
                        Spacer()
                        Button {
                            SMAppService.openSystemSettingsLoginItems()
                        } label: {
                            Text("Open Login Items…", comment: "Mac setting action")
                        }
                    }
                }
                if let failure {
                    Text(failure)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text(
                    "Closing the last window keeps Aloha Social running, so notifications keep coming. Quit it with ⌘Q.",
                    comment: "Mac setting footer")
            }
        }
        .formStyle(.grouped)
        // The person can change it in System Settings while this is open.
        .onAppear { status = SMAppService.mainApp.status }
    }

    private func setOpensAtLogin(_ isOn: Bool) {
        failure = nil
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = String(
                localized: "That did not work: \(error.localizedDescription)",
                comment: "Mac setting: open at login failed")
        }
        status = SMAppService.mainApp.status
    }
}
