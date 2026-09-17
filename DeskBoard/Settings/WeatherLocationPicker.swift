import SwiftUI

struct WeatherLocationPicker: View {
    @ObservedObject var store: WeatherLocationStore
    @StateObject private var model: WeatherLocationSearchModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var retry = 0

    init(store: WeatherLocationStore, initialQuery: String = "", provider: WeatherLocationSearching = OpenMeteoLocationProvider()) {
        self.store = store
        _query = State(initialValue: initialQuery)
        _model = StateObject(wrappedValue: WeatherLocationSearchModel(provider: provider))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weather Location").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("Search cities (e.g. Seoul)", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    message("Enter at least two characters to find a city.")
                } else if model.isSearching {
                    ProgressView("Searching…").controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.errorMessage {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { retry += 1 }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.results.isEmpty {
                    message("No matching cities. Try the city's English name.")
                } else {
                    List(model.results) { location in
                        Button {
                            store.select(location)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(location.name)
                                    if !location.regionDescription.isEmpty {
                                        Text(location.regionDescription).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if location.id == store.selected.id {
                                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            Link("City search by Open-Meteo", destination: URL(string: "https://open-meteo.com/en/docs/geocoding-api")!)
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 440, height: 420)
        .task(id: "\(retry):\(query)") { await model.search(query) }
        .onAppear { searchFocused = true }
    }

    private func message(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
