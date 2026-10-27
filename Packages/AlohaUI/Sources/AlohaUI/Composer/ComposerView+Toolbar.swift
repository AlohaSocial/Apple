// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaIntelligence
import AlohaModels
import SwiftUI

#if canImport(ImagePlayground) && !os(tvOS) && !os(watchOS)
    import ImagePlayground
#endif

/// The tool row under the editor: media, poll, visibility, the menu of
/// everything else, and the pickers that open from it.
extension ComposerView {
    var toolbar: some View {
        HStack(spacing: AlohaMetrics.space3) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    toolbarButtons
                }
                .buttonStyle(ComposerToolStyle())
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            if let remaining = model.remainingCharacters {
                Text(remaining, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(remaining < 0 ? palette.destructive : palette.secondaryLabel)
                    .fixedSize()
                    .accessibilityLabel(
                        Text(
                            "^[\(remaining) character](inflect: true) left",
                            comment: "Composer counter"))
            }
        }
        .font(.title3)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space3)
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        Button {
            model.isShowingMediaPicker = true
        } label: {
            Image(systemName: AlohaSymbol.media)
        }
        .disabled(!model.canAddMedia)
        .accessibilityLabel(Text("Add media", comment: "Composer action"))

        #if os(iOS)
            if CameraCapture.isAvailable {
                Button {
                    isShowingCamera = true
                } label: {
                    Image(systemName: "camera")
                }
                .disabled(!model.canAddMedia)
                .accessibilityLabel(Text("Take a photo or video", comment: "Composer action"))
            }
        #endif

        #if os(iOS) || os(macOS) || os(visionOS)
            // The system's paste button reads the pasteboard only when tapped,
            // so a copied picture is attached without the "allow paste"
            // prompt, and it greys itself out when nothing pasteable is there.
            PasteButton(payloadType: DroppedMedia.self) { items in
                Task { await attach(items) }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .disabled(!model.canAddMedia)
        #endif

        Button {
            if !model.hasPoll { model.togglePoll() }
            isShowingPollEditor = true
        } label: {
            Image(systemName: AlohaSymbol.poll)
        }
        .disabled(!model.attachments.isEmpty)
        .accessibilityLabel(Text("Add a poll", comment: "Composer action"))

        Menu {
            Picker(selection: $model.visibility) {
                Label {
                    Text("Public", comment: "Visibility")
                } icon: {
                    Image(systemName: AlohaSymbol.globe)
                }.tag(Visibility.public)
                Label {
                    Text("Unlisted", comment: "Visibility")
                } icon: {
                    Image(systemName: "eye.slash")
                }.tag(Visibility.unlisted)
                Label {
                    Text("Followers only", comment: "Visibility")
                } icon: {
                    Image(systemName: AlohaSymbol.lock)
                }.tag(Visibility.private)
                Label {
                    Text("Direct", comment: "Visibility")
                } icon: {
                    Image(systemName: AlohaSymbol.envelope)
                }.tag(Visibility.direct)
            } label: {
                Text("Visibility", comment: "Composer picker")
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: model.visibilitySymbol)
        }
        .accessibilityLabel(Text("Who can see this", comment: "Composer action"))

        Menu {
            if model.canBeCard {
                Button {
                    showsCardOptions.toggle()
                } label: {
                    Label {
                        Text("Post it as a card", comment: "Composer action")
                    } icon: {
                        Image(systemName: "rectangle.on.rectangle")
                    }
                }
                .accessibilityLabel(Text("Post it as a card", comment: "Composer card section"))
                .accessibilityValue(
                    showsCardOptions
                        ? Text("Expanded", comment: "Accessibility state")
                        : Text("Collapsed", comment: "Accessibility state"))
            }
            Button {
                model.showsContentWarningField.toggle()
            } label: {
                Label {
                    Text("Add a content warning", comment: "Composer action")
                } icon: {
                    Image(systemName: AlohaSymbol.warning)
                }
            }
            .accessibilityLabel(Text("Add a content warning", comment: "Composer action"))

            Button {
                model.addThreadSegment()
            } label: {
                Label {
                    Text("Add to thread", comment: "Composer action")
                } icon: {
                    Image(systemName: "text.append")
                }
            }
            // A thread and a time do not go together: a scheduled post has
            // nothing for the next one to reply to until it is out.
            .disabled(model.scheduledAt != nil)
            .accessibilityLabel(Text("Add to thread", comment: "Composer action"))

            Button {
                isShowingSchedule = true
            } label: {
                Label {
                    Text("Schedule this post", comment: "Composer action")
                } icon: {
                    Image(systemName: model.scheduledAt == nil ? "clock" : "clock.fill")
                }
            }
            .disabled(model.isThread && model.scheduledAt == nil)
            .accessibilityLabel(Text("Schedule this post", comment: "Composer action"))

            if model.capabilities.mediaFromNextcloudFiles {
                Button {
                    isShowingNextcloudFiles = true
                } label: {
                    Label {
                        Text("Attach from your Nextcloud", comment: "Composer action")
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
                .disabled(!model.canAddMedia)
                .accessibilityLabel(
                    Text("Attach from your Nextcloud", comment: "Composer action"))
            }

            if model.isNextcloud {
                Button {
                    isShowingGIFPicker = true
                } label: {
                    Label {
                        Text("Add a picture from the library", comment: "Composer action")
                    } icon: {
                        Image(systemName: "photo.stack")
                    }
                }
                .disabled(!model.canAddMedia)
                .accessibilityLabel(
                    Text("Add a picture from the library", comment: "Composer action"))

                Button {
                    isShowingPlacePicker = true
                } label: {
                    Label {
                        Text("Add a place", comment: "Composer action")
                    } icon: {
                        Image(
                            systemName: model.place == nil
                                ? "mappin.and.ellipse" : "mappin.circle.fill")
                    }
                }
                .accessibilityLabel(Text("Add a place", comment: "Composer action"))
            }

            Button {
                isShowingEmojiPicker = true
            } label: {
                Label {
                    Text("Add a custom emoji", comment: "Composer action")
                } icon: {
                    Image(systemName: "face.smiling")
                }
            }
            .accessibilityLabel(Text("Add a custom emoji", comment: "Composer action"))

            Menu {
                LanguagePicker(language: $model.language, fallback: model.defaultLanguage)
            } label: {
                if let code = model.language, !code.isEmpty {
                    Text(LanguagePicker.short(for: code))
                        .font(.caption.weight(.bold))
                        .frame(minWidth: 24, minHeight: 24)
                } else {
                    Label {
                        Text("Language", comment: "Composer action")
                    } icon: {
                        Image(systemName: "character.book.closed")
                    }
                }
            }
            .accessibilityLabel(Text("Language", comment: "Composer action"))

            if model.canQuote, model.editingStatus == nil {
                Menu {
                    Picker(selection: $model.quotePolicy) {
                        Label {
                            Text("Anybody", comment: "Quote policy")
                        } icon: {
                            Image(systemName: AlohaSymbol.globe)
                        }.tag(ComposerModel.QuotePolicy.public)
                        Label {
                            Text("People who follow me", comment: "Quote policy")
                        } icon: {
                            Image(systemName: "person.2")
                        }.tag(ComposerModel.QuotePolicy.followers)
                        Label {
                            Text("Nobody but me", comment: "Quote policy")
                        } icon: {
                            Image(systemName: AlohaSymbol.lock)
                        }.tag(ComposerModel.QuotePolicy.nobody)
                    } label: {
                        Text("Who may quote this", comment: "Composer picker")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label {
                        Text("Who may quote this", comment: "Composer action")
                    } icon: {
                        Image(
                            systemName: model.quotePolicy == .public
                                ? "text.quote" : "text.badge.xmark")
                    }
                }
                .accessibilityLabel(Text("Who may quote this", comment: "Composer action"))
            }

            if model.isNextcloud, model.editingStatus == nil {
                Menu {
                    Picker(selection: $model.replyPolicy) {
                        ForEach(ReplyPolicy.allCases, id: \.self) { policy in
                            ReplyPolicyLabel(policy: policy).tag(policy)
                        }
                    } label: {
                        Text("Who can reply", comment: "Composer picker")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label {
                        Text("Who can reply", comment: "Composer action")
                    } icon: {
                        Image(systemName: ReplyPolicyLabel.symbol(model.replyPolicy))
                    }
                }
                .accessibilityLabel(Text("Who can reply", comment: "Composer action"))

                Toggle(isOn: $model.marksAsAIGenerated) {
                    Label {
                        Text("Made with AI", comment: "Composer toggle")
                    } icon: {
                        Image(systemName: "wand.and.sparkles")
                    }
                }
                .accessibilityHint(
                    Text(
                        "Adds #AIgenerated, which readers can choose to filter.",
                        comment: "Composer toggle hint"))
            }

            if !model.teams.isEmpty {
                Menu {
                    Picker(selection: $model.postAs) {
                        Text("Myself", comment: "Post as option").tag(TeamAccount?.none)
                        ForEach(model.teams) { team in
                            Text(team.name).tag(TeamAccount?.some(team))
                        }
                    } label: {
                        Text("Post as", comment: "Composer picker")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label {
                        Text("Post as", comment: "Composer action")
                    } icon: {
                        Image(systemName: model.postAs == nil ? "person" : "person.3.fill")
                    }
                }
                .accessibilityLabel(Text("Post as", comment: "Composer action"))
            }

            #if canImport(ImagePlayground) && !os(tvOS) && !os(watchOS)
                if supportsImagePlayground {
                    Button {
                        isShowingImagePlayground = true
                    } label: {
                        Label {
                            Text("Create an image", comment: "Composer action")
                        } icon: {
                            Image(systemName: "apple.image.playground")
                        }
                    }
                    .disabled(!model.canAddMedia)
                }
            #endif

            if environment.intelligence.availability.isAvailable {
                Menu {
                    ForEach(RewriteStyle.allCases) { style in
                        Button {
                            rewritingStyle = style
                        } label: {
                            Text(style.displayName)
                        }
                    }
                } label: {
                    Label {
                        Text("Writing help", comment: "Composer action")
                    } icon: {
                        Image(systemName: AlohaSymbol.sparkles)
                    }
                }
                .disabled(model.text.isEmpty)
                .accessibilityLabel(Text("Writing help", comment: "Composer action"))
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text("More options", comment: "Composer additional actions"))
        // Each picker comes out of the button it was chosen from: a popover
        // on an iPad or a Mac, where a full sheet over the composer hid the
        // post being written, and a sheet on a phone, where a popover would
        // be a postage stamp.
        .composerPicker(isPresented: $isShowingSchedule) {
            SchedulePicker(scheduledAt: $model.scheduledAt)
        }
        .composerPicker(isPresented: $isShowingPlacePicker) {
            if let session = environment.activeSession {
                PlacePicker(session: session) { model.place = $0 }
            }
        }
        .composerPicker(isPresented: $isShowingGIFPicker) {
            if let session = environment.activeSession {
                GIFPicker(session: session) { entry in
                    Task { await model.attachLibraryPicture(entry) }
                }
            }
        }
        .composerPicker(isPresented: $isShowingEmojiPicker) {
            if let session = environment.activeSession {
                EmojiPicker(session: session) { insertAtCursor(":\($0.shortcode):") }
            }
        }
        #if canImport(ImagePlayground) && !os(tvOS) && !os(watchOS)
            .imagePlaygroundSheet(
                isPresented: $isShowingImagePlayground,
                concepts: model.text.isEmpty ? [] : [.extracted(from: model.text, title: nil)]
            ) { url in
                Task { await attachPlaygroundImage(at: url) }
            }
        #endif
    }

    /// An image made in Image Playground goes up like any other picture, and
    /// the post is marked as made with AI where the server can carry that:
    /// the label is the honest default for a picture the person did not take.
    private func attachPlaygroundImage(at url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        let image = DroppedImage(data: data)
        await model.uploader.add(
            data: image.data, filename: image.filename, mimeType: image.mimeType)
        if model.isNextcloud { model.marksAsAIGenerated = true }
    }
}

/// The composer's tool row: tinted glyphs at the text size the person reads
/// at, each with a hit area that grows with it.
///
/// Glass is the navigation layer's material, not a control's inside the
/// content; a row of glass circles under the text read as a second toolbar
/// floating over the post. A fixed 18-point glyph also ignored Dynamic Type.
private struct ComposerToolStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.medium))
            .frame(minWidth: side, minHeight: side)
            .contentShape(Rectangle())
            .foregroundStyle(.tint)
            .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.6 : 1))
    }
}

extension View {
    /// A composer picker: a popover in regular width and on the Mac, a sheet
    /// in compact width, sized so a search field and a grid of results have
    /// room either way.
    fileprivate func composerPicker<Content: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        popover(isPresented: isPresented, arrowEdge: .bottom) {
            content()
                .frame(minWidth: 320, idealWidth: 400, minHeight: 420, idealHeight: 560)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
        }
    }
}
