import SwiftUI

struct PendingRequestsView: View {
    private struct PendingRequest: Identifiable {
        let request: SeerrRequest
        let media: SeerrMedia

        var id: Int { request.id }
    }

    struct ApprovalEnvelopeButton: View {
        @ObservedObject var session: SeerrSession
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: session.pendingApprovalCount > 0 ? "envelope.open" : "envelope")
            }
            .accessibilityLabel("Pending requests")
            .accessibilityValue("\(session.pendingApprovalCount)")
        }
    }

    @ObservedObject var session: SeerrSession
    @Environment(\.dismiss) private var dismiss
    @State private var requests: [PendingRequest] = []
    @State private var workingRequestIDs = Set<Int>()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if requests.isEmpty && error == nil {
                    ContentUnavailableView("No pending requests", systemImage: "checkmark.circle")
                        .listRowBackground(Color.clear)
                }
                ForEach(requests) { pending in
                    Section {
                        requestRow(pending)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle("Pending Requests")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .task { await load() }
        }
    }

    private func requestRow(_ pending: PendingRequest) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: pending.media.artworkURL) { $0.resizable().scaledToFill() } placeholder: {
                Color.gray.opacity(0.18).overlay(Image(systemName: "film"))
            }
            .frame(width: 58, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(pending.media.displayTitle).font(.headline).lineLimit(2)
                Text(pending.media.isTV ? "TV show" : "Movie")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let release = pending.media.releaseText {
                    Text(release).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                actionButton("checkmark", tint: .green, request: pending.request, approve: true)
                actionButton("xmark", tint: .red, request: pending.request, approve: false)
            }
        }
    }

    private func actionButton(_ image: String, tint: Color, request: SeerrRequest, approve: Bool) -> some View {
        Button {
            Task { await update(request, approve: approve) }
        } label: {
            Image(systemName: image)
                .font(.caption.bold())
                .frame(width: 30, height: 30)
                .foregroundStyle(.white)
                .background(tint, in: Circle())
        }
        .buttonStyle(.borderless)
        .disabled(workingRequestIDs.contains(request.id))
        .accessibilityLabel(approve ? "Approve request" : "Decline request")
    }

    private func load() async {
        guard let api = session.api else { return }
        do {
            let pending = try await api.approvalRequests()
            requests = await withTaskGroup(of: PendingRequest?.self, returning: [PendingRequest].self) { group in
                for request in pending {
                    group.addTask { await presentation(for: request, api: api) }
                }
                var rows: [PendingRequest] = []
                for await row in group {
                    if let row { rows.append(row) }
                }
                return rows.sorted { $0.request.id > $1.request.id }
            }
            error = nil
            await session.refreshPendingApprovalCount()
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }

    private func presentation(for request: SeerrRequest, api: SeerrAPI) async -> PendingRequest? {
        guard let source = request.media else { return nil }
        if source.title != nil || source.name != nil {
            return PendingRequest(request: request, media: source)
        }
        do {
            if request.mediaType == "tv" || source.isTV {
                let details = try await api.tv(id: source.requestableID)
                return PendingRequest(request: request, media: SeerrMedia(
                    id: details.id, name: details.name, mediaType: "tv", posterPath: details.posterPath, firstAirDate: details.firstAirDate
                ))
            }
            let details = try await api.movie(id: source.requestableID)
            return PendingRequest(request: request, media: SeerrMedia(
                id: details.id, title: details.title, mediaType: "movie", posterPath: details.posterPath, releaseDate: details.releaseDate
            ))
        } catch {
            return PendingRequest(request: request, media: source)
        }
    }

    private func update(_ request: SeerrRequest, approve: Bool) async {
        guard let api = session.api else { return }
        workingRequestIDs.insert(request.id)
        defer { workingRequestIDs.remove(request.id) }
        do {
            _ = try await (approve ? api.approveRequest(id: request.id) : api.declineRequest(id: request.id))
            requests.removeAll { $0.request.id == request.id }
            await session.refreshPendingApprovalCount()
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }
}
