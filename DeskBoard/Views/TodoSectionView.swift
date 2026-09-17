import SwiftUI
import SwiftData

struct TodoSectionView: View {
    @Environment(\.compactSidebarSections) private var compact
    @Binding var isAdding: Bool
    let availableHeight: CGFloat
    @State private var scrollRequest = 0
    @State private var pendingInsertedItem: TodoItem?
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\TodoItem.sortOrder), SortDescriptor(\TodoItem.createdAt)]) private var items: [TodoItem]
    @State private var draft = ""
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 10) {
            HStack {
                SectionTitle(text: "Todo")
                Button("+") {
                    isAdding = true
                    scrollRequest += 1
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .help("New Todo")
            }
            if items.isEmpty && !isAdding { PlaceholderText(text: "Add your first task") }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, item in
                            TodoRow(
                                item: item,
                                delete: { context.delete(item) },
                                moveEarlier: index > 0 ? { swap(item, items[index - 1]) } : nil,
                                moveLater: index < items.count - 1 ? { swap(item, items[index + 1]) } : nil
                            )
                        }
                        if isAdding {
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .foregroundStyle(.tertiary)
                                TextField("New task", text: $draft)
                                    .textFieldStyle(.plain)
                                    .font(DashboardTypography.item)
                                    .focused($isDraftFocused)
                                    .onSubmit(add)
                                    .onExitCommand(perform: cancelAdding)
                                Button(action: add) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .tertiary : .secondary)
                                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .help("Add Todo")
                            }
                        }
                        Color.clear.frame(height: 1).id("todo-bottom")
                    }
                    .padding(.bottom, 5)
                }
                .scrollIndicators(.hidden)
                .task(id: TodoScrollRequest(
                    generation: scrollRequest,
                    height: isAdding || pendingInsertedItem != nil ? availableHeight : 0,
                    itemCount: pendingInsertedItem != nil ? items.count : 0
                )) {
                    guard scrollRequest > 0, isAdding || pendingInsertedItem != nil else { return }
                    // Wait for the new row and the resized viewport to participate in layout.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo("todo-bottom", anchor: .bottom)
                    if isAdding { isDraftFocused = true }
                    if let pendingInsertedItem, items.contains(where: { $0 === pendingInsertedItem }) {
                        self.pendingInsertedItem = nil
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, compact ? 4 : 13)
        .onDisappear { cancelAdding() }
    }

    private func cancelAdding() {
        draft = ""
        isAdding = false
        isDraftFocused = false
        pendingInsertedItem = nil
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let item = TodoItem(title: title, sortOrder: (items.map(\.sortOrder).max() ?? -1) + 1)
        pendingInsertedItem = item
        context.insert(item)
        scrollRequest += 1
        draft = ""
        isAdding = false
        isDraftFocused = false
    }

    private func swap(_ first: TodoItem, _ second: TodoItem) {
        let value = first.sortOrder
        first.sortOrder = second.sortOrder
        second.sortOrder = value
    }
}

private struct TodoScrollRequest: Equatable {
    let generation: Int
    let height: CGFloat
    let itemCount: Int
}

private struct TodoRow: View {
    @Bindable var item: TodoItem
    let delete: () -> Void
    let moveEarlier: (() -> Void)?
    let moveLater: (() -> Void)?
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editDraft = ""
    @FocusState private var isEditFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button { item.isCompleted.toggle() } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)
            if isEditing {
                HStack(spacing: 6) {
                    TextField("Todo", text: $editDraft)
                        .textFieldStyle(.plain)
                        .font(DashboardTypography.item)
                        .focused($isEditFocused)
                        .onSubmit(commitEdit)
                    Button(action: commitEdit) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text(item.title)
                    .font(DashboardTypography.item)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .tertiary : .primary)
                    .onTapGesture(count: 2, perform: beginEditing)
                    .help("Double-click to edit")
            }
            Spacer(minLength: 4)
            if isHovering {
                Button(action: delete) { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            if let moveEarlier { Button("Move Earlier", action: moveEarlier) }
            if let moveLater { Button("Move Later", action: moveLater) }
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private func beginEditing() {
        editDraft = item.title
        isEditing = true
        DispatchQueue.main.async { isEditFocused = true }
    }

    private func commitEdit() {
        let value = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        item.title = value
        isEditing = false
        isEditFocused = false
    }
}
