import AppKit
import SwiftUI
import SwiftData

struct MemoSectionView: View {
    @Environment(\.compactSidebarSections) private var compact
    @Environment(\.modelContext) private var context
    @Query private var documents: [MemoDocument]
    let availableWidth: CGFloat
    let onPreferredHeightChange: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 9) {
            SectionTitle(text: "Memo")
            if let document = documents.first {
                MemoEditor(
                    document: document,
                    availableWidth: availableWidth,
                    onPreferredHeightChange: onPreferredHeightChange
                )
            }
        }
        .padding(.vertical, compact ? 4 : 13)
        .task {
            if documents.isEmpty { context.insert(MemoDocument()) }
        }
    }
}

private struct MemoEditor: View {
    @Bindable var document: MemoDocument
    let availableWidth: CGFloat
    let onPreferredHeightChange: (CGFloat) -> Void
    @FocusState private var isFocused: Bool
    @State private var layoutCommitTask: Task<Void, Never>?

    var body: some View {
        TextEditor(text: $document.text)
            .font(.system(size: 13))
            .focused($isFocused)
            .defaultFocus($isFocused, false)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(.clear)
            .overlay(alignment: .topLeading) {
                if document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFocused {
                    Text("Write a note…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: document.text) {
                document.updatedAt = .now
                scheduleLayoutCommit()
            }
            .onChange(of: isFocused) {
                if !isFocused { commitLayout() }
            }
            .onChange(of: availableWidth) { scheduleLayoutCommit() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                isFocused = false
            }
            .onAppear { commitLayout() }
            .onDisappear { layoutCommitTask?.cancel() }
    }

    private func scheduleLayoutCommit() {
        layoutCommitTask?.cancel()
        let text = document.text
        let width = availableWidth
        layoutCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            onPreferredHeightChange(preferredHeight(for: text, width: width))
        }
    }

    private func commitLayout() {
        layoutCommitTask?.cancel()
        onPreferredHeightChange(preferredHeight(for: document.text, width: availableWidth))
    }

    private func preferredHeight(for text: String, width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let measurementText = text.isEmpty ? " " : text + "\n "
        let bounds = (measurementText as NSString).boundingRect(
            with: NSSize(width: max(80, width - 12), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let sectionChrome: CGFloat = 52
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let rawHeight = sectionChrome + max(lineHeight, ceil(bounds.height))
        let rowStep: CGFloat = 24
        return max(180, ceil(rawHeight / rowStep) * rowStep)
    }
}
