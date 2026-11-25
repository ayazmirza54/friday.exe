import AppKit
import SwiftUI

/// Debug aid: `Bol --render-threads <dir>` renders the Threads window, on each thread found on this Mac,
/// to PNGs for design review.
enum ThreadsPreview {
	@MainActor static func render(to directory: String) {
		try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
		let store = ThreadStore()
		store.start()
		wait(until: { store.hasLoadedList })
		let ids = store.threads.map(\.id)
		print("\(ids.count) thread(s), \(store.missingCount) missing")
		// Each thread, then the newest task (opened from its thread), as the last image.
		let task = store.tasks.last { $0.transcriptURL != nil }
		let views: [(id: String?, task: TaskSummary?)] =
			(ids.isEmpty ? [(nil, nil)] : ids.map { ($0, nil) }) + (task.map { [($0.threadId, $0)] } ?? [])
		for (index, view) in views.enumerated() {
			let id = view.id
			store.openTaskId = nil
			store.selectedId = id
			if let task = view.task { store.show(task: task) }
			wait(until: { id == nil || store.transcript != nil })
			if let transcript = store.transcript {
				print(
					"\(index): \(transcript.items.count) items, context \(transcript.contextTokens ?? 0), \(store.selected?.title.prefix(60) ?? "")"
				)
			}
			let controller = NSHostingController(
				rootView: ThreadsView(store: store, actions: ThreadsActions()).environment(\.colorScheme, .dark))
			let window = NSWindow(contentViewController: controller)
			window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
			window.titlebarAppearsTransparent = true
			window.appearance = NSAppearance(named: .darkAqua)
			window.setContentSize(NSSize(width: 1080, height: 740))
			window.orderFront(nil)
			RunLoop.current.run(until: Date().addingTimeInterval(0.8))
			guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
				continue
			}
			view.cacheDisplay(in: view.bounds, to: rep)
			try? rep.representation(using: .png, properties: [:])?.write(
				to: URL(fileURLWithPath: directory).appendingPathComponent("threads-\(index).png"))
			window.close()
		}
		store.stop()
	}

	@MainActor private static func wait(until isDone: () -> Bool) {
		let deadline = Date().addingTimeInterval(15)
		while !isDone(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
	}
}
