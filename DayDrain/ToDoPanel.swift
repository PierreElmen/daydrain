import SwiftUI
import AppKit

struct ToDoPanel: View {
    @ObservedObject var manager: ToDoManager
    var openSettings: () -> Void
    var quitApplication: () -> Void

    @State private var isVisible = false
    @FocusState private var focusedTaskID: FocusTask.ID?

    private let panelWidth: CGFloat = 280

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily Focus")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.top, 4)

                Text("Three anchors for today. Keep them light, keep them honest.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                ForEach(manager.tasks) { task in
                    FocusTaskRow(
                        task: task,
                        isHighlighted: manager.highlightedTaskID == task.id,
                        tooltip: manager.highlightedTaskID == task.id ? manager.tooltip : nil,
                        onToggle: { manager.toggleTaskCompletion(for: task.id) },
                        onTextChange: { manager.updateTaskText(for: task.id, text: $0) },
                        onClear: { manager.clearTask(task.id) }
                    )
                    .focused($focusedTaskID, equals: task.id)
                    .transition(.asymmetric(insertion: .offset(y: -12).combined(with: .opacity), removal: .opacity))
                }
            }

            Divider()
                .padding(.vertical, 2)

            HStack(spacing: 12) {
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(PanelButtonStyle())

                Button(action: quitApplication) {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(PanelButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: panelWidth)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -12)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isVisible)
        .onAppear {
            isVisible = true
            focusedTaskID = manager.focusedTaskID
        }
        .onReceive(manager.$focusedTaskID) { focusedTaskID = $0 }
    }
}

private struct PanelBackground: View {
    var body: some View {
        VisualEffectBlur(material: .menu, blendingMode: .withinWindow)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(.primary.opacity(configuration.isPressed ? 0.5 : 0.75))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.07 : 0.05))
            )
    }
}

private struct FocusTaskRow: View {
    let task: FocusTask
    let isHighlighted: Bool
    let tooltip: String?
    let onToggle: () -> Void
    let onTextChange: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(task.label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(isHighlighted ? Color.orange.opacity(0.9) : Color.secondary)
                if isHighlighted {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.orange)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Spacer()
                if task.done {
                    Text("Complete")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color.green.opacity(0.75))
                        .transition(.opacity)
                }
            }

            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.done ? Color.green : Color.secondary.opacity(0.8))
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.plain)

                TextField("Add focus…", text: Binding(
                    get: { task.text },
                    set: { onTextChange($0) }
                ), axis: .vertical)
                    .lineLimit(1...2)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .disableAutocorrection(true)
                    .padding(.vertical, 6)

                if !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .opacity(0.85)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(task.done ? 0.08 : 0.12))
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(highlightBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(isHighlighted ? 0.45 : 0.0), lineWidth: 1)
                .shadow(color: Color.orange.opacity(isHighlighted ? 0.25 : 0), radius: isHighlighted ? 6 : 0)
        )
        .optionalHelp(tooltip)
        .animation(.easeInOut(duration: 0.25), value: task.done)
        .animation(.easeInOut(duration: 0.25), value: isHighlighted)
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isHighlighted
                        ? [Color.orange.opacity(0.18), Color.orange.opacity(0.05)]
                        : [Color.primary.opacity(0.04), Color.primary.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private extension View {
    @ViewBuilder
    func optionalHelp(_ text: String?) -> some View {
        if let text {
            help(text)
        } else {
            self
        }
    }
}
