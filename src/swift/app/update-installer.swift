import AppKit
import CryptoKit
import Security

/// Downloads, checks and installs a release in place. Every step refuses rather than guesses: the DMG must
/// match the feed's SHA-256, and the app inside must have Bol's bundle id, a higher build, a valid signature
/// from the same Developer ID team as the running app, and pass Gatekeeper. Same bundle id and team means
/// macOS keeps every permission across the update.
enum UpdateInstaller {
	enum Failure: LocalizedError, Equatable {
		case notInstallable(String)
		case checksumMismatch
		case badPackage(String)
		case untrusted(String)

		var errorDescription: String? {
			switch self {
			case .notInstallable(let why): return why
			case .checksumMismatch: return "The download didn't match the published checksum."
			case .badPackage(let why): return "The update package isn't right: \(why)."
			case .untrusted(let why): return "The update isn't signed by Bol's developer: \(why)."
			}
		}
	}

	private static let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
	private static let spctl = URL(fileURLWithPath: "/usr/sbin/spctl")

	/// Where the running app is, if Bol may replace it there (a signed release in a folder it can write to).
	static func installableLocation() -> Result<URL, Failure> {
		let app = Bundle.main.bundleURL
		guard app.pathExtension == "app" else { return .failure(.notInstallable("Bol isn't running as an app.")) }
		guard teamID(of: app) != nil else {
			return .failure(.notInstallable("This build isn't a signed release, so it doesn't update itself."))
		}
		if app.path.contains("/AppTranslocation/") {
			return .failure(.notInstallable("Move Bol to Applications to let it update itself."))
		}
		guard FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
			return .failure(.notInstallable("Bol can't write to \(app.deletingLastPathComponent().path)."))
		}
		return .success(app)
	}

	/// Downloads the DMG and checks it against the feed's SHA-256.
	static func download(release: Release, session: URLSession) async throws -> URL {
		guard let expected = release.sha256?.lowercased(), expected.count == 64 else {
			throw Failure.badPackage("the feed has no checksum")
		}
		let (temporary, response) = try await session.download(from: release.url)
		guard (response as? HTTPURLResponse)?.statusCode == 200 else {
			throw Failure.badPackage("the download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
		}
		let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("Bol-\(release.build).dmg")
		try? FileManager.default.removeItem(at: dmg)
		try FileManager.default.moveItem(at: temporary, to: dmg)
		guard try sha256(file: dmg) == expected else {
			try? FileManager.default.removeItem(at: dmg)
			throw Failure.checksumMismatch
		}
		return dmg
	}

	static func sha256(file: URL) throws -> String {
		let handle = try FileHandle(forReadingFrom: file)
		defer { try? handle.close() }
		var hasher = SHA256()
		while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
		return hasher.finalize().map { String(format: "%02x", $0) }.joined()
	}

	/// Mounts the DMG, checks the app inside, and copies it next to `replacing` (same volume, so the final
	/// swap is atomic). Returns the staged app.
	static func stage(dmg: URL, release: Release, replacing current: URL) async throws -> URL {
		let mount = FileManager.default.temporaryDirectory.appendingPathComponent("bol-update-\(release.build)")
		try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
		let attached = await Shell.run(
			executable: hdiutil,
			arguments: ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path],
			timeoutSeconds: 120)
		guard attached.isSuccess else { throw Failure.badPackage("the disk image wouldn't open") }
		defer {
			Task { _ = await Shell.run(executable: hdiutil, arguments: ["detach", mount.path, "-force"]) }
		}
		let app = mount.appendingPathComponent("Bol.app")
		try await verify(app: app, release: release, against: current)
		let staged = current.deletingLastPathComponent().appendingPathComponent(".Bol-update-\(release.build).app")
		try? FileManager.default.removeItem(at: staged)
		try FileManager.default.copyItem(at: app, to: staged)
		try await verify(app: staged, release: release, against: current)  // the copy, too
		try? FileManager.default.removeItem(at: dmg)
		return staged
	}

	static func verify(app: URL, release: Release, against current: URL) async throws {
		guard let info = Bundle(url: app)?.infoDictionary else { throw Failure.badPackage("no Bol.app inside") }
		guard info["CFBundleIdentifier"] as? String == Bundle(url: current)?.bundleIdentifier else {
			throw Failure.badPackage("a different app's bundle id")
		}
		guard (info["CFBundleVersion"] as? String).flatMap({ Int($0) }) == release.build else {
			throw Failure.badPackage("its build doesn't match the release")
		}
		guard isValidlySigned(app: app) else { throw Failure.untrusted("its signature doesn't check out") }
		guard let team = teamID(of: app), team == teamID(of: current) else {
			throw Failure.untrusted("a different signing team")
		}
		let gatekeeper = await Shell.run(executable: spctl, arguments: ["--assess", "--type", "execute", app.path])
		guard gatekeeper.isSuccess else { throw Failure.untrusted("Gatekeeper rejected it") }
	}

	/// Swaps the staged app in for the running one. The running process keeps working until it quits.
	static func install(staged: URL, replacing current: URL) throws {
		_ = try FileManager.default.replaceItemAt(current, withItemAt: staged)
	}

	/// Opens the app again a moment after this process has quit.
	static func relaunch(app: URL) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
		try? process.run()
	}

	static func teamID(of app: URL) -> String? {
		var code: SecStaticCode?
		guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
		var info: CFDictionary?
		guard
			SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
			let dictionary = info as? [String: Any]
		else { return nil }
		return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
	}

	private static func isValidlySigned(app: URL) -> Bool {
		var code: SecStaticCode?
		guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
		let flags = SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate | kSecCSCheckAllArchitectures)
		return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
	}
}
