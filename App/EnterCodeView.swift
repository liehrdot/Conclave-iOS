import ConclaveCore
import SwiftUI

/// Pairing by typing: the code from the PC, plus the server's address. A pasted pairing link
/// carries the address itself, so the server field goes away for it.
struct EnterCodeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var server = ""
    @State private var busy = false
    @State private var problem: String?
    @FocusState private var focus: Field?

    enum Field { case code, server }

    private var isLink: Bool { code.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("http") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ABCD-EFGH or pairing link", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .code)
                        .submitLabel(isLink ? .go : .next)
                } header: {
                    Text("Code")
                } footer: {
                    Text("On your PC: Settings › Sync › Pair a device. A code works once, for 15 minutes.")
                }
                if !isLink {
                    Section {
                        TextField("sync.example.org", text: $server)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .server)
                            .submitLabel(.go)
                    } header: {
                        Text("Server")
                    } footer: {
                        Text("The address of your sync server or of Conclave Cloud.")
                    }
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(busy)
            .navigationTitle("Enter Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Connect") { connect() }
                            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onSubmit {
                if focus == .code && !isLink { focus = .server } else { connect() }
            }
            .onAppear { focus = .code }
            .interactiveDismissDisabled(busy)
            .sensoryFeedback(.error, trigger: problem) { _, new in new != nil }
        }
    }

    private func connect() {
        guard !busy else { return }
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                try await model.pair(code, server: server)
                dismiss()
            } catch {
                problem = Connection.message(for: error)
            }
        }
    }
}
