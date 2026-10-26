import ConclaveCore
import SwiftUI

extension View {
    /// The outbox's line under a tab's content on the iPad, and on the iPhone before iOS 26.1: the
    /// toast with "Undo" right after a save, else the changes the server refused, else a quiet note
    /// that changes wait to be sent, as a pill on the floating layer above the tab bar. Mirrors the
    /// PWA's toast with "Rückgängig" and its quiet status line (`screens.js`).
    func outboxStatus() -> some View {
        modifier(OutboxPill())
    }

    /// The same line on the iPhone from iOS 26.1 on, as the tab bar's bottom accessory: Apple's place
    /// for a status that belongs to the whole app, like the Music app's player (HIG, Tab bars). The
    /// system draws the glass and the size, and hides it while there's nothing to say.
    func outboxAccessory() -> some View {
        modifier(OutboxAccessory())
    }
}

/// Whether this device shows the status as the tab bar's accessory. The iPad keeps the pill: its tab
/// bar sits at the top, and an accessory bar would sit away from the content it reports on.
@MainActor
private var usesAccessory: Bool {
    guard #available(iOS 26.1, *) else { return false }
    return UIDevice.current.userInterfaceIdiom == .phone
}

private struct OutboxPill: ViewModifier {
    func body(content: Content) -> some View {
        if usesAccessory {
            content
        } else {
            content.safeAreaInset(edge: .bottom) { OutboxStatus(inAccessory: false) }
        }
    }
}

private struct OutboxAccessory: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: usesAccessory && model.hasOutboxStatus) {
                OutboxStatus(inAccessory: true)
            }
        } else {
            content
        }
    }
}

extension AppModel {
    /// Whether the outbox has anything to say: a fresh save, refused changes or changes waiting.
    var hasOutboxStatus: Bool { saved != nil || !refused.isEmpty || !waiting.isEmpty }
}

private struct OutboxStatus: View {
    /// In the tab bar's accessory the system draws the glass and sets the height; else it's our own pill.
    let inAccessory: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
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
                    Button { Task { await model.undo(saved.op) } } label: {
                        Text("Undo").font(.body.weight(.semibold)).padding(.horizontal, 10).frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
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
                        Label(count(model.refused.count, "change wasn't saved", "changes weren't saved", short: "not saved"),
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
                        Label(count(model.waiting.count, "change waiting to be sent", "changes waiting to be sent",
                                    short: "waiting"),
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

    @ViewBuilder
    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if inAccessory {
            HStack(spacing: 12, content: content)
                .font(.body)
                .lineLimit(1)
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
        } else {
            HStack(spacing: 12, content: content)
                .font(.body)
                .lineLimit(1)
                // an even margin around the Undo button, so the pill is clearly bigger than it
                .padding(.leading, 20)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
                .frame(minHeight: 64)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal)
                .padding(.vertical, 8)
                // the gaps around the pill catch taps too, so a near miss never opens the card beneath it
                .contentShape(.rect)
                .onTapGesture {}
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// "3 changes waiting to be sent"; inline next to a minimized tab bar there's only room for "3 waiting".
    private func count(_ number: Int, _ one: String, _ many: String, short: String) -> String {
        if inAccessory, placement == .inline { return "\(number) \(short)" }
        return number == 1 ? "1 \(one)" : "\(number) \(many)"
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
