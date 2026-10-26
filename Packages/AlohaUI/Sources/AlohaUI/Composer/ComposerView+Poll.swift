// SPDX-License-Identifier: MIT

import AlohaDesign
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
            }
            .font(.footnote)
            Toggle(isOn: $model.pollMultiple) {
                Text("Multiple choice", comment: "Poll option")
            }
            .toggleStyle(.switch)
        }
        .padding(AlohaMetrics.space3)
    }
}
