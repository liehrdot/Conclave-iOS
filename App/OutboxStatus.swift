import ConclaveCore
import SwiftUI

extension View {
    /// The outbox's line at the bottom of a tab, above the tab bar: the toast with "Undo" right after a
    /// save, else the changes the server refused, else a quiet note that changes wait to be sent.
    /// Mirrors the PWA's toast with "Rückgängig" and its quiet status line (`screens.js`).
    func outboxStatus() -> some View {
        safeAreaInset(edge: .bottom) { OutboxStatus() }
    }
}

private struct OutboxStatus: View {
    @Environment(AppModel.self) private var model
    @State private var showingRefused = false
    /// How long the toast stays (the PWA's is a few seconds too).
    private static let toastFor: Duration = .seconds(6)

    var body: some View {
        Group {
            if let saved = model.saved {
                pill {
                    Label(saved.text, systemImage: "checkmark.circle.fill")
                        .labelStyle(Tinted(color: Color.accentColor))
                    Spacer(minLength: 8)
                    Button("Undo") { Task { await model.undo(saved.op) } }
                        .font(.subheadline.weight(.semibold))
                }
                .task(id: saved.id) {
                    try? await Task.sleep(for: Self.toastFor)
                    if model.saved?.id == saved.id { withAnimation { model.saved = nil } }
                }
            } else if !model.refused.isEmpty {
                Button {
                    showingRefused = true
                } label: {
                    pill {
                        Label(count(model.refused.count, "change wasn't saved", "changes weren't saved"),
                              systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(Tinted(color: .orange))
                        Spacer(minLength: 8)
                        Text("Why?").font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            } else if !model.waiting.isEmpty {
                // quiet on purpose: offline at the table is normal, and nothing is lost
                Button {
                    Task { await model.send(force: true) }
                } label: {
                    pill {
                        Label(count(model.waiting.count, "change waiting to be sent", "changes waiting to be sent"),
                              systemImage: "clock")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Tries to send now")
            }
        }
        .animation(.snappy, value: model.saved)
        .animation(.snappy, value: model.ops)
        .sheet(isPresented: $showingRefused) { RefusedChanges() }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func count(_ number: Int, _ one: String, _ many: String) -> String {
        number == 1 ? "1 \(one)" : "\(number) \(many)"
    }
}

/// A label whose icon has its own colour and whose text stays primary.
private struct Tinted: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}

/// The changes the server refused, each with its reason (the server's words, in German) and
/// "Dismiss". They are already gone from the screens: a refused change is never shown as done.
private struct RefusedChanges: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.refused) { op in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(op.summary(in: model.library)).font(.headline)
                            if let error = op.error, !error.isEmpty {
                                Text(error).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions { Button("Dismiss") { Task { await model.dismiss(op) } } }
                    }
                } footer: {
                    Text("Your server didn't take these, for the reason shown (it answers in German). Swipe to dismiss one.")
                }
            }
            .navigationTitle("Not Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Dismiss All") {
                        Task { for op in model.refused { await model.dismiss(op) } }
                        dismiss()
                    }
                }
            }
            .overlay {
                if model.refused.isEmpty { ContentUnavailableView("All Saved", systemImage: "checkmark.circle") }
            }
        }
    }
}
