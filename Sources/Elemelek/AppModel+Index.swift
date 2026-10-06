import ElemelekCore
import Foundation
import MatrixRustSDK

extension AppModel {
    // MARK: Local index

    /// The SDK indexes every message it processes, decrypted ones included, into the local search store. So that
    /// old messages are searchable too, page back through each room once in the background.
    func startIndexing() {
        indexTask?.cancel()
        let done = IndexedRooms().ids
        let todo = roomObjects.filter { !done.contains($0.id()) }
        indexTotal = roomObjects.count
        indexDone = roomObjects.count - todo.count
        guard !todo.isEmpty else { return }
        indexTask = Task { [weak self] in
            for room in todo {
                if Task.isCancelled { return }
                var complete = false
                if let t = try? await room.timelineWithConfiguration(configuration: TimelineConfiguration(
                    focus: .live(hideThreadedEvents: false), filter: .all, internalIdPrefix: "index-",
                    dateDividerMode: .daily, trackReadReceipts: .disabled, reportUtds: false)) {
                    var pages = 0
                    while pages < 100, !Task.isCancelled {
                        let hit = (try? await t.paginateBackwards(numEvents: 50)) ?? false
                        pages += 1
                        if hit { complete = true; break }
                        try? await Task.sleep(nanoseconds: 120_000_000)
                    }
                }
                guard let self else { return }
                await MainActor.run {
                    self.indexDone += 1
                    if complete {
                        IndexedRooms().insert(room.id())
                    }
                }
            }
        }
    }
}
