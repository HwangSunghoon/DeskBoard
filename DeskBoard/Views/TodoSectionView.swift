import SwiftUI
import SwiftData

struct TodoSectionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\TodoItem.sortOrder), SortDescriptor(\TodoItem.createdAt)]) private var items: [TodoItem]
    @State private var draft = ""
    @State private var isAdding = false
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Todo")
                Button("+") {
                    if isAdding {
                        isDraftFocused = true
                    } else {
                        isAdding = true
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .help("New Todo")
            }
            if items.isEmpty && !isAdding { PlaceholderText(text: "Add your first task") }
            ScrollView {
                LazyVStack(spacing: 7) {
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
                }
                .padding(.bottom, 5)
            }
            .scrollIndicators(.hidden)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .onChange(of: isAdding) {
            if isAdding {
                DispatchQueue.main.async { isDraftFocused = true }
            }
        }
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        context.insert(TodoItem(title: title, sortOrder: (items.map(\.sortOrder).max() ?? -1) + 1))
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
