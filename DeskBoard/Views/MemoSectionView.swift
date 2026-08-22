import SwiftUI
import SwiftData

struct MemoSectionView: View {
    @Environment(\.modelContext) private var context
    @Query private var documents: [MemoDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(text: "Today’s Plan")
            if let document = documents.first { MemoEditor(document: document) }
        }
        .padding(.vertical, 13)
        .task {
            if documents.isEmpty { context.insert(MemoDocument()) }
        }
    }
}

private struct MemoEditor: View {
    @Bindable var document: MemoDocument

    var body: some View {
        TextEditor(text: $document.text)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .background(.clear)
            .overlay(alignment: .topLeading) {
                if document.text.isEmpty {
                    Text("Write a note…")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .padding(.leading, 7)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: document.text) { document.updatedAt = .now }
    }
}
