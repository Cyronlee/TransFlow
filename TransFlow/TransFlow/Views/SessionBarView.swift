import SwiftUI

/// Fixed top bar displaying the current session filename and a button to create a new session.
struct SessionBarView: View {
    let sessionName: String
    let onNewSession: (String) -> Void

    @State private var showingNewSessionSheet = false
    @State private var newSessionName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                // Session filename in the center
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)

                    Text(sessionName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // New session button on the right
                Button {
                    newSessionName = JSONLStore.generateDefaultName()
                    showingNewSessionSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "session.new_session"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.background)

            // Subtle bottom border
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
        .sheet(isPresented: $showingNewSessionSheet) {
            newSessionSheet
        }
    }

    // MARK: - New Session Sheet

    private var newSessionSheet: some View {
        VStack(spacing: 16) {
            Text("session.new_session")
                .font(.system(size: 15, weight: .semibold))

            TextField("session.filename_placeholder", text: $newSessionName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 280)

            HStack(spacing: 12) {
                Button("session.cancel") {
                    showingNewSessionSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("session.create") {
                    let name = newSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        onNewSession(name)
                    }
                    showingNewSessionSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
    }
}
