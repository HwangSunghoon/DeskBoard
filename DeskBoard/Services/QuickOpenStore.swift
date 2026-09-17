import AppKit
import Combine
import Foundation
import SwiftUI

struct QuickOpenApplication: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let bundleIdentifier: String
    let path: String
    let bookmarkData: Data

    func resolvedURL() -> URL? {
        var isStale = false
        if let bookmarkedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            let access = bookmarkedURL.startAccessingSecurityScopedResource()
            defer { if access { bookmarkedURL.stopAccessingSecurityScopedResource() } }
            if FileManager.default.fileExists(atPath: bookmarkedURL.path) { return bookmarkedURL }
        }

        let storedURL = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: storedURL.path) {
            return storedURL
        }

        guard !bundleIdentifier.isEmpty else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

@MainActor
final class QuickOpenStore: ObservableObject {
    static let shared = QuickOpenStore()
    static let maximumApplicationCount = 6

    @Published private(set) var applications: [QuickOpenApplication]

    private let defaults: UserDefaults
    private let storageKey = "quickOpenApplications.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let savedApplications = try? JSONDecoder().decode([QuickOpenApplication].self, from: data) {
            applications = Array(savedApplications.prefix(Self.maximumApplicationCount))
        } else {
            applications = []
        }
    }

    func addApplication(at selectedURL: URL) throws {
        guard applications.count < Self.maximumApplicationCount else {
            throw QuickOpenStoreError.maximumApplicationsReached
        }

        let applicationURL = selectedURL.standardizedFileURL
        guard applicationURL.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: applicationURL) else {
            throw QuickOpenStoreError.invalidApplication
        }

        let bundleIdentifier = bundle.bundleIdentifier ?? ""
        let isDuplicate = applications.contains { application in
            (!bundleIdentifier.isEmpty && application.bundleIdentifier == bundleIdentifier)
                || URL(fileURLWithPath: application.path).standardizedFileURL == applicationURL
        }
        guard !isDuplicate else { throw QuickOpenStoreError.applicationAlreadyAdded }

        let didAccess = applicationURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { applicationURL.stopAccessingSecurityScopedResource() }
        }

        let bookmarkData: Data
        do {
            bookmarkData = try applicationURL.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw QuickOpenStoreError.couldNotSaveAccess
        }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let name = [displayName, bundleName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? applicationURL.deletingPathExtension().lastPathComponent

        applications.append(
            QuickOpenApplication(
                id: UUID(),
                name: name,
                bundleIdentifier: bundleIdentifier,
                path: applicationURL.path,
                bookmarkData: bookmarkData
            )
        )
        save()
    }

    func removeApplication(id: UUID) {
        applications.removeAll { $0.id == id }
        save()
    }

    /// Refresh moved/stale bookmarks only on a user action, never during view rendering.
    func urlForOpening(_ application: QuickOpenApplication) -> URL? {
        guard let url = application.resolvedURL() else { return nil }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var stale = false
        _ = try? URL(resolvingBookmarkData: application.bookmarkData, options: [.withSecurityScope, .withoutUI],
                     relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale || url.path != application.path,
           let data = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil),
           let index = applications.firstIndex(where: { $0.id == application.id }) {
            applications[index] = QuickOpenApplication(id: application.id, name: application.name,
                bundleIdentifier: application.bundleIdentifier, path: url.path, bookmarkData: data)
            save()
        }
        return url
    }

    func moveApplication(id: UUID, by offset: Int) {
        guard let sourceIndex = applications.firstIndex(where: { $0.id == id }) else { return }
        let destinationIndex = sourceIndex + offset
        guard applications.indices.contains(destinationIndex) else { return }
        applications.swapAt(sourceIndex, destinationIndex)
        save()
    }

    func moveApplications(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, source.allSatisfy(applications.indices.contains),
              (0...applications.count).contains(destination) else { return }
        applications.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(applications) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

private enum QuickOpenStoreError: LocalizedError {
    case maximumApplicationsReached
    case invalidApplication
    case applicationAlreadyAdded
    case couldNotSaveAccess

    var errorDescription: String? {
        switch self {
        case .maximumApplicationsReached:
            "Quick Open supports up to six applications."
        case .invalidApplication:
            "Select a valid macOS application."
        case .applicationAlreadyAdded:
            "That application is already in Quick Open."
        case .couldNotSaveAccess:
            "DeskBoard could not save access to that application."
        }
    }
}
