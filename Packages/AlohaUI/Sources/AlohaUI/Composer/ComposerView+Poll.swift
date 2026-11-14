// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// The poll editor, shown in its own sheet.
extension ComposerView {
    var pollEditor: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            Text(
                "Add at least two choices. People can vote after you publish the post.",
                comment: "Poll editor guidance"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            ForEach(model.pollOptions.indices, id: \.self) { index in
                HStack {
                    TextField(
                        text: Binding(
                            get: {
                                model.pollOptions.indices.contains(index)
                                    ? model.pollOptions[index] : ""
                            },
                            set: { value in
                                guard model.pollOptions.indices.contains(index) else { return }
                                model.pollOptions[index] = value
                            }),
                        prompt: Text("Choice \(index + 1)", comment: "Poll option placeholder")
                    ) {
                        Text("Choice", comment: "Poll option label")
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)
                    optionCounter(index)
                    Button(role: .destructive) {
                        guard model.pollOptions.count > 2,
                            model.pollOptions.indices.contains(index)
                        else { return }
                        model.pollOptions.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.pollOptions.count <= 2)
                    .accessibilityLabel(Text("Remove choice", comment: "Poll editor action"))
                }
            }

            HStack {
                Button {
                    model.addPollOption()
                } label: {
                    Text("Add choice", comment: "Poll action")
                }
                .disabled(model.pollOptions.count >= model.limits.maxPollOptions)
                .buttonStyle(.bordered)

                Spacer()

                // The server's own ceiling, said before the button greys out.
                Text(
                    "Up to \(model.limits.maxPollOptions) choices",
                    comment: "Poll editor: the server's maximum number of choices"
                )
                .foregroundStyle(.secondary)
            }
            .font(.footnote)

            if let problem = model.pollProblem {
                Label {
                    Text(problem.message)
                } icon: {
                    Image(systemName: AlohaSymbol.warning)
                }
                .font(.footnote)
                .foregroundStyle(palette.destructive)
            }

            Picker(selection: $model.pollExpiresIn) {
                ForEach(model.pollDurations, id: \.self) { seconds in
                    Text(PollRules.label(for: seconds)).tag(seconds)
                }
            } label: {
                Text("Ends after", comment: "Poll duration picker")
            }
            Toggle(isOn: $model.pollMultiple) {
                Text("Multiple choice", comment: "Poll option")
            }
            .toggleStyle(.switch)
            Toggle(isOn: $model.pollHideTotals) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide results until it ends", comment: "Poll option")
                    Text(
                        "Voters see the counts only once the poll has closed.",
                        comment: "Poll option detail"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(AlohaMetrics.space3)
        // A draft from another server, or the default on one that caps polls
        // at an hour, is moved onto a duration this server offers, so the
        // picker never shows a blank choice.
        .onAppear {
            model.pollExpiresIn = PollRules.closestDuration(
                to: model.pollExpiresIn, within: model.limits)
        }
    }

    /// Characters left in one choice, shown as it nears the server's
    /// `max_characters_per_option` and in red past it.
    @ViewBuilder
    private func optionCounter(_ index: Int) -> some View {
        let option = model.pollOptions.indices.contains(index) ? model.pollOptions[index] : ""
        let remaining = PollRules.remaining(in: option, limits: model.limits)
        if remaining <= 10 {
            Text(remaining, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(remaining < 0 ? palette.destructive : palette.secondaryLabel)
                .fixedSize()
                .accessibilityLabel(
                    Text(
                        "^[\(remaining) character](inflect: true) left",
                        comment: "Poll option counter"))
        }
    }
}
