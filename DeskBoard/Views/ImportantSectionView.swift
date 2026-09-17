import SwiftUI
import SwiftData

struct ImportantSectionView: View {
    @Environment(\.compactSidebarSections) private var compact
    @Binding var isAdding: Bool
    @FocusState private var isDraftFocused: Bool
    @Environment(\.modelContext) private var context
    @Query private var items: [ImportantItem]
    @State private var title = ""
    @State private var date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 9) {
            HStack {
                SectionTitle(text: "Important")
                Button("+") {
                    isAdding = true
                    isDraftFocused = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .help("New Important Item")
            }
            if isAdding {
                HStack(spacing: 7) {
                    TextField("Event Title", text: $title)
                        .textFieldStyle(.plain)
                        .focused($isDraftFocused)
                        .onSubmit(add)
                        .onExitCommand(perform: cancelAdding)
                    ImportantDateButton(date: $date)
                    Button(action: add) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Add Important Item")
                }
                .font(DashboardTypography.item)
            }
            if items.isEmpty && !isAdding {
                PlaceholderText(text: "Pin a date or reminder")
            }
            ScrollView(.vertical) {
                LazyVStack(spacing: 6) {
                    ForEach(Array(sortedItems.enumerated()), id: \.element.persistentModelID) { index, item in
                        let orderedItems = sortedItems
                        ImportantRow(
                            item: item,
                            delete: { context.delete(item) },
                            moveEarlier: index > 0 && canReorder(item, with: orderedItems[index - 1]) ? { swap(item, orderedItems[index - 1]) } : nil,
                            moveLater: index < orderedItems.count - 1 && canReorder(item, with: orderedItems[index + 1]) ? { swap(item, orderedItems[index + 1]) } : nil
                        )
                    }
                }
                .padding(.bottom, 5)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, compact ? 4 : 12)
        .task(id: isAdding) {
            if isAdding {
                await Task.yield()
                isDraftFocused = true
            }
        }
        .onDisappear { cancelAdding() }
    }

    private func cancelAdding() {
        title = ""
        date = nil
        isAdding = false
        isDraftFocused = false
    }

    private func add() {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        context.insert(ImportantItem(title: value, date: date, sortOrder: (items.map(\.sortOrder).max() ?? -1) + 1))
        cancelAdding()
    }

    private func swap(_ first: ImportantItem, _ second: ImportantItem) {
        let value = first.sortOrder
        first.sortOrder = second.sortOrder
        second.sortOrder = value
    }

    private var sortedItems: [ImportantItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return items.sorted { first, second in
            let firstGroup = dateGroup(first.date, relativeTo: today, calendar: calendar)
            let secondGroup = dateGroup(second.date, relativeTo: today, calendar: calendar)
            if firstGroup != secondGroup { return firstGroup < secondGroup }

            switch (first.date, second.date) {
            case let (firstDate?, secondDate?):
                let firstDay = calendar.startOfDay(for: firstDate)
                let secondDay = calendar.startOfDay(for: secondDate)
                if firstDay != secondDay {
                    return firstGroup == 1 ? firstDay > secondDay : firstDay < secondDay
                }
            default:
                break
            }
            return first.sortOrder < second.sortOrder
        }
    }

    private func dateGroup(_ date: Date?, relativeTo today: Date, calendar: Calendar) -> Int {
        guard let date else { return 2 }
        return calendar.startOfDay(for: date) >= today ? 0 : 1
    }

    private func canReorder(_ first: ImportantItem, with second: ImportantItem) -> Bool {
        switch (first.date, second.date) {
        case (nil, nil):
            return true
        case let (firstDate?, secondDate?):
            return Calendar.current.isDate(firstDate, inSameDayAs: secondDate)
        default:
            return false
        }
    }
}

private struct ImportantRow: View {
    let item: ImportantItem
    let delete: () -> Void
    let moveEarlier: (() -> Void)?
    let moveLater: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            if let date = item.date {
                Text(importantDateText(date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .leading)
            }
            Text(item.title).font(DashboardTypography.item).lineLimit(1)
            Spacer(minLength: 3)
            if hovering {
                Button(action: delete) { Image(systemName: "xmark").font(.system(size: 9)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if let moveEarlier { Button("Move Earlier", action: moveEarlier) }
            if let moveLater { Button("Move Later", action: moveLater) }
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct ImportantDateButton: View {
    @Binding var date: Date?
    @AppStorage("sidebarSide") private var sidebarSide = "right"
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Text(dateText)
                .font(.system(size: 11))
                .foregroundStyle(date == nil ? .tertiary : .secondary)
                .monospacedDigit()
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: $isPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: sidebarSide == "right" ? .trailing : .leading
        ) {
            CompactDatePicker(selectedDate: date) { selected in
                date = selected
                isPresented = false
            }
            .onExitCommand { isPresented = false }
        }
        .contextMenu {
            if date != nil {
                Button("Clear Date") { date = nil }
            }
        }
    }

    private var dateText: String {
        guard let date else { return "Date" }
        return importantDateText(date)
    }
}

private func importantDateText(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return "~\(components.year ?? 0)/\(components.month ?? 0)/\(components.day ?? 0)"
}
