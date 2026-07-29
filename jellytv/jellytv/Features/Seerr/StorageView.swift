import SwiftUI

struct StorageView: View {
    @ObservedObject var session: JellyfinSession
    @Environment(\.dismiss) private var dismiss
    @State private var storage: JellyfinSystemStorage?
    @State private var drives: [JellyfinDrive] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isRefreshingLibraries = false
    @State private var libraryRefreshMessage: String?
    @State private var libraryRefreshProgress: Double?

    private var locations: [JellyfinStorageLocation] {
        storage?.locations ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let error {
                    ContentUnavailableView(
                        "Storage Unavailable",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(error)
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section("Fixed Locations") {
                        storageRows(fixedLocations, fixedDrives)
                    }

                    Section("Network") {
                        storageRows(networkLocations, networkDrives)
                    }

                    Section("Library") {
                        Button("Rescan Libraries") { Task { await refreshLibraries() } }
                            .disabled(isRefreshingLibraries)
                        if isRefreshingLibraries {
                            if let libraryRefreshProgress {
                                ProgressView(value: libraryRefreshProgress)
                            } else {
                                ProgressView()
                            }
                        }
                        if let libraryRefreshMessage, !isRefreshingLibraries {
                            Text(libraryRefreshMessage).foregroundStyle(.red)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Storage")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task(id: session.account?.token) { await load() }
            .refreshable { await load() }
        }
    }

    private func storageLocation(for drive: JellyfinDrive) -> JellyfinStorageLocation? {
        guard let drivePath = drive.path?.trimmingCharacters(in: .whitespacesAndNewlines), !drivePath.isEmpty else {
            return nil
        }

        let prefix = drivePath.hasSuffix("/") || drivePath.hasSuffix("\\") ? drivePath : drivePath + "/"
        return locations.first { location in
            location.path == drivePath || location.path?.hasPrefix(prefix) == true
        }
    }

    private var fixedLocations: [JellyfinStorageLocation] {
        locations.filter { !isNetwork($0) }
    }

    private var networkLocations: [JellyfinStorageLocation] {
        locations.filter(isNetwork)
    }

    private var fixedDrives: [JellyfinDrive] {
        drives.filter { !isNetwork($0) }
    }

    private var networkDrives: [JellyfinDrive] {
        drives.filter(isNetwork)
    }

    @ViewBuilder
    private func storageRows(_ locations: [JellyfinStorageLocation], _ drives: [JellyfinDrive]) -> some View {
        if locations.isEmpty, drives.isEmpty {
            Text("No locations")
                .foregroundStyle(.secondary)
        } else {
            ForEach(locations) { location in
                StorageUsageDetails(location: location)
            }

            ForEach(drives) { drive in
                if let location = storageLocation(for: drive) {
                    StorageUsageDetails(
                        location: location,
                        titleOverride: "\(drive.name ?? "Drive") Drive",
                        pathOverride: drive.path,
                        storageTypeOverride: drive.type
                    )
                } else {
                    DriveDetails(drive: drive)
                }
            }
        }
    }

    private func isNetwork(_ location: JellyfinStorageLocation) -> Bool {
        location.storageType?.caseInsensitiveCompare("Network") == .orderedSame
    }

    private func isNetwork(_ drive: JellyfinDrive) -> Bool {
        storageLocation(for: drive).map(isNetwork) ?? false
    }

    private func load() async {
        guard let api = session.api else {
            isLoading = false
            error = "Sign in to view storage."
            return
        }

        isLoading = true
        error = nil
        do {
            async let systemStorage = api.systemStorage()
            async let availableDrives = api.drives()
            storage = try await systemStorage
            drives = (try? await availableDrives) ?? []
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func refreshLibraries() async {
        guard let api = session.api else { return }
        isRefreshingLibraries = true
        libraryRefreshMessage = nil
        libraryRefreshProgress = nil
        do {
            try await api.refreshLibraries()
            await monitorLibraryRefresh(using: api)
        } catch {
            session.handle(error)
            libraryRefreshMessage = error.localizedDescription
            isRefreshingLibraries = false
        }
    }

    private func monitorLibraryRefresh(using api: JellyfinAPI) async {
        var refreshWasRunning = false

        for attempt in 0 ..< 3_600 {
            do {
                if let task = try await api.libraryRefreshTask() {
                    if task.isRunning {
                        refreshWasRunning = true
                        let progress = min(max((task.currentProgressPercentage ?? 0) / 100, 0), 1)
                        libraryRefreshProgress = progress
                        libraryRefreshMessage = "Refreshing library…"
                    } else if refreshWasRunning {
                        libraryRefreshProgress = 1
                        libraryRefreshMessage = nil
                        isRefreshingLibraries = false
                        return
                    } else if attempt >= 10 {
                        libraryRefreshMessage = nil
                        isRefreshingLibraries = false
                        return
                    }
                } else if attempt >= 10 {
                    libraryRefreshMessage = nil
                    isRefreshingLibraries = false
                    return
                }
                try await Task.sleep(for: .seconds(1))
            } catch {
                session.handle(error)
                libraryRefreshMessage = error.localizedDescription
                isRefreshingLibraries = false
                return
            }
        }

        libraryRefreshMessage = nil
        isRefreshingLibraries = false
    }
}

private struct StorageUsageDetails: View {
    let location: JellyfinStorageLocation
    var titleOverride: String?
    var pathOverride: String?
    var storageTypeOverride: String?

    private var path: String? { pathOverride ?? location.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            HStack {
                Text(titleOverride ?? location.name)
                    .font(.headline)
                Spacer()
                if let path {
                    Text(path)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let usedFraction = location.usedFraction,
               let usedSpace = location.usedSpace,
               let freeSpace = location.freeSpace
            {
                ProgressView(value: usedFraction)
                    .tint(usedFraction > 0.9 ? .red : usedFraction > 0.75 ? .orange : .accentColor)

                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: usedSpace, countStyle: .file)) used")
                    Spacer()
                    Text("\(ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)) free")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Text("Capacity unavailable")
                    .foregroundStyle(.secondary)
            }
            
            if let storageType = storageTypeOverride ?? location.storageType,
               let totalSpace = location.totalSpace
            {
                HStack {
                    Text(storageType)
                    Spacer()
                    Text("\(ByteCountFormatter.string(fromByteCount: totalSpace, countStyle: .file)) total")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DriveDetails: View {
    let drive: JellyfinDrive

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(drive.name ?? "Drive") Drive")
                .font(.headline)
            if let path = drive.path {
                Text(path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let type = drive.type {
                Text(type)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    StorageView(session: JellyfinSession())
}
