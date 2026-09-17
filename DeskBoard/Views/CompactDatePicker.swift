import SwiftUI

struct CalendarMonth {
    let start: Date
    let calendar: Calendar

    init(containing date: Date, calendar: Calendar) {
        self.calendar = calendar
        start = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let cellCount = ((leading + range.count + 6) / 7) * 7
        return (0..<cellCount).map { index in
            let day = index - leading + 1
            guard range.contains(day) else { return nil }
            return calendar.date(byAdding: .day, value: day - 1, to: start)
        }
    }

    func shifted(by offset: Int) -> Date {
        calendar.date(byAdding: .month, value: offset, to: start) ?? start
    }
}

struct CompactDatePicker: View {
    let selectedDate: Date?
    let onSelect: (Date) -> Void
    @State private var displayedMonth: Date
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = .current
        value.firstWeekday = Calendar.current.firstWeekday
        return value
    }
    private var month: CalendarMonth { CalendarMonth(containing: displayedMonth, calendar: calendar) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    init(selectedDate: Date?, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.onSelect = onSelect
        _displayedMonth = State(initialValue: selectedDate ?? .now)
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 4) {
                Text(monthTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                monthButton("chevron.left", offset: -1, label: "Previous Month")
                monthButton("chevron.right", offset: 1, label: "Next Month")
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(height: 18)
                        .accessibilityHidden(true)
                }
                ForEach(Array(month.days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayButton(day)
                    } else {
                        Color.clear.frame(height: 26).accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 240)
        .buttonStyle(.plain)
    }

    private func monthButton(_ image: String, offset: Int, label: String) -> some View {
        Button { displayedMonth = month.shifted(by: offset) } label: {
            Image(systemName: image)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .help(label)
        .accessibilityLabel(label)
    }

    private func dayButton(_ day: Date) -> some View {
        let selected = selectedDate.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
        return Button { onSelect(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background {
                    if selected { Circle().fill(Color.primary.opacity(0.12)) }
                }
                .overlay(alignment: .bottom) {
                    if calendar.isDateInToday(day) {
                        Circle().fill(Color.secondary).frame(width: 3, height: 3).offset(y: -1)
                    }
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: month.start)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        return formatter.shortStandaloneWeekdaySymbols
    }
}
