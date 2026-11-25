import AppKit
import UserNotifications

/// A published release, as served by agentbol.com/latest.json (website/public/latest.json).
struct Release: Decodable, Equatable {
	let version: String
	/// Monotonic build number (CFBundleVersion); the only thing compared.
	let build: Int
	/// The DMG.
	let url: URL
	let minimumSystemVersion: String?
	let notes: String?

	/// Whether this release should be offered to an app at `currentBuild` on macOS `systemVersion`.
	func isUpdate(currentBuild: Int, systemVersion: OperatingSystemVersion) -> Bool {
		guard build > currentBuild else { return false }
		guard let minimumSystemVersion else { return true }
		let minimum = minimumSystemVersion.split(separator: ".").map { Int($0) ?? 0 } + [0, 0, 0]
		let system = [systemVersion.majorVersion, systemVersion.minorVersion, systemVersion.patchVersion]
		return !system.lexicographicallyPrecedes(minimum.prefix(3))
	}
}

/// Polls the update feed and, when a newer build is out, notifies once per release and offers it in the menu.
/// Installing stays manual: the notification and menu item open the DMG download.
final class UpdateChecker: NSObject, UNUserNotificationCenterDelegate {
	/// The newer release, once one is found.
	private(set) var available: Release?
	var onChange: (() -> Void)?

	private let feedURL: URL
	private let session: URLSession
	private let currentBuild: Int?
	private let defaults: UserDefaults
	/// Shows the notification; the default posts a macOS notification (tests pass their own).
	private let present: (Release) async -> Bool
	private var timer: Timer?
	private static let notifiedBuildKey = "BolNotifiedUpdateBuild"
	/// Dev-only override, to try updates against a local feed: `defaults write com.agentbol.bol BolUpdateFeedURL <url>`.
	static let feedOverrideKey = "BolUpdateFeedURL"
	fileprivate static let notificationCategory = "update"

	init(
		feedURL: URL? = nil, session: URLSession = .shared,
		currentBuild: Int? = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0) },
		defaults: UserDefaults = .standard, present: ((Release) async -> Bool)? = nil
	) {
		self.feedURL =
			feedURL ?? defaults.string(forKey: Self.feedOverrideKey).flatMap { URL(string: $0) }
			?? Constants.updateFeedURL
		self.session = session
		self.currentBuild = currentBuild
		self.defaults = defaults
		self.present = present ?? UpdateChecker.postNotification
		super.init()
	}

	func start() {
		// Unbundled runs (swift run, tests) have no build number to compare.
		guard currentBuild != nil, Bundle.main.bundleIdentifier != nil else { return }
		UNUserNotificationCenter.current().delegate = self
		let timer = Timer(timeInterval: Constants.updateCheckSeconds, repeats: true) { [weak self] _ in
			Task { await self?.check() }
		}
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
		Task {
			try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)  // stay out of the way of launch
			await check()
		}
	}

	func openDownload() {
		guard let available else { return }
		NSWorkspace.shared.open(available.url)
	}

	/// Reads the feed once: updates `available` (calling `onChange` when it changes) and notifies about a
	/// release it hasn't notified about before.
	@MainActor func check() async {
		guard let currentBuild else { return }
		var request = URLRequest(url: feedURL)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.timeoutInterval = 20
		do {
			let (data, response) = try await session.data(for: request)
			guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
			let release = try JSONDecoder().decode(Release.self, from: data)
			let update =
				release.isUpdate(
					currentBuild: currentBuild, systemVersion: ProcessInfo.processInfo.operatingSystemVersion)
				? release : nil
			guard update != available else { return }
			available = update
			onChange?()
			if let update { await notify(release: update) }
		} catch {
			Log.info(message: "update check failed: \(error.localizedDescription)")
		}
	}

	@MainActor private func notify(release: Release) async {
		guard defaults.integer(forKey: Self.notifiedBuildKey) < release.build else { return }
		guard await present(release) else { return }
		defaults.set(release.build, forKey: Self.notifiedBuildKey)
		Log.info(message: "update available: \(release.version) (\(release.build))")
	}

	/// Asks for notification permission only now that there's something to say.
	private static func postNotification(release: Release) async -> Bool {
		let center = UNUserNotificationCenter.current()
		guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
		let content = UNMutableNotificationContent()
		content.title = "Bol \(release.version) is available"
		content.body = release.notes.map { "\($0) Click to download." } ?? "Click to download the update."
		content.categoryIdentifier = notificationCategory
		let request = UNNotificationRequest(identifier: "update-\(release.build)", content: content, trigger: nil)
		do {
			try await center.add(request)
			return true
		} catch {
			Log.info(message: "update notification failed: \(error.localizedDescription)")
			return false
		}
	}

	func userNotificationCenter(
		_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		if response.notification.request.content.categoryIdentifier == Self.notificationCategory {
			DispatchQueue.main.async { self.openDownload() }
		}
		completionHandler()
	}

	/// Show the banner even though Bol (a menu bar app) counts as frontmost while its menu or windows are open.
	func userNotificationCenter(
		_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		completionHandler([.banner, .sound])
	}
}
