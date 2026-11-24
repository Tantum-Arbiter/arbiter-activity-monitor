import Foundation
import CryptoKit
import Security

/// A dotted numeric version such as 0.2.0. A leading "v" is accepted so release tags parse directly.
public struct AppVersion: Comparable, Sendable, Equatable, CustomStringConvertible {
    public let parts: [Int]
    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= 6, piece.allSatisfy(\.isASCII), piece.allSatisfy(\.isNumber), let number = Int(piece) else { return nil }
            parts.append(number)
        }
        self.parts = parts
    }
    public var description: String { parts.map(String.init).joined(separator: ".") }
    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for index in 0..<max(a.parts.count, b.parts.count) {
            let x = index < a.parts.count ? a.parts[index] : 0, y = index < b.parts.count ? b.parts[index] : 0
            if x != y { return x < y }
        }
        return false
    }
    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

public struct ReleaseInfo: Sendable, Equatable {
    public let version: AppVersion
    public let assetName: String
    public let download: URL
    public let size: Int
    /// Lowercase hex SHA-256 of the asset, as published by the release feed.
    public let sha256: String
}

public enum UpdateError: Error, Equatable, LocalizedError {
    case feed(String), noAsset, download(String), checksum, unpack, invalidBundle(String), location(String), install(String)
    public var errorDescription: String? {
        switch self {
        case .feed(let reason): "Could not read the release feed: \(reason)"
        case .noAsset: "The latest release has no Apple silicon download with a checksum"
        case .download(let reason): "Download failed: \(reason)"
        case .checksum: "The download did not match the published checksum and was discarded"
        case .unpack: "The download could not be unpacked"
        case .invalidBundle(let reason): "The downloaded app was rejected: \(reason)"
        case .location(let reason): reason
        case .install(let reason): "The update could not be installed: \(reason)"
        }
    }
}

/// Where updates come from. The feed is GitHub's "latest release" JSON for the public repository.
public struct UpdateSource: Sendable {
    public var feed: URL
    /// Downloads are accepted only from URLs with this prefix.
    public var downloadPrefix: String
    public var assetSuffix: String
    public init(feed: URL, downloadPrefix: String, assetSuffix: String = "-macos-arm64.zip") {
        self.feed = feed; self.downloadPrefix = downloadPrefix; self.assetSuffix = assetSuffix
    }
    public static let github = UpdateSource(
        feed: URL(string: "https://api.github.com/repos/Tantum-Arbiter/arbiter-activity-monitor/releases/latest")!,
        downloadPrefix: "https://github.com/Tantum-Arbiter/arbiter-activity-monitor/releases/download/")

    /// Accepts only a published (non-draft, non-prerelease) release with a zip for this architecture and a SHA-256 digest.
    public func parse(_ data: Data) throws -> ReleaseInfo {
        struct Feed: Decodable {
            struct Asset: Decodable { let name: String; let size: Int; let digest: String?; let browser_download_url: String }
            let tag_name: String; let draft: Bool?; let prerelease: Bool?; let assets: [Asset]
        }
        guard data.count <= 1_048_576, let feed = try? JSONDecoder().decode(Feed.self, from: data) else { throw UpdateError.feed("unexpected response") }
        guard feed.draft != true, feed.prerelease != true, let version = AppVersion(feed.tag_name) else { throw UpdateError.feed("no published version") }
        for asset in feed.assets where asset.name.hasSuffix(assetSuffix) {
            guard let digest = asset.digest, digest.hasPrefix("sha256:") else { continue }
            let hex = String(digest.dropFirst(7)).lowercased()
            guard hex.count == 64, hex.allSatisfy(\.isHexDigit), asset.browser_download_url.hasPrefix(downloadPrefix),
                  let url = URL(string: asset.browser_download_url), asset.size > 0, asset.size <= 268_435_456 else { continue }
            return ReleaseInfo(version: version, assetName: asset.name, download: url, size: asset.size, sha256: hex)
        }
        throw UpdateError.noAsset
    }
}

/// Checks for, verifies and installs a newer build. This is the app's only network access: one request for the
/// release feed and, on install, one download. Nothing about this Mac or its sessions is sent.
public actor Updater {
    private let source: UpdateSource
    private let session: URLSession
    private let userAgent: String

    public init(source: UpdateSource = .github, currentVersion: String = "") {
        self.source = source
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        userAgent = "arbiter-activity-monitor" + (currentVersion.isEmpty ? "" : "/" + currentVersion)
    }

    public func latest() async throws -> ReleaseInfo {
        var request = URLRequest(url: source.feed)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw UpdateError.feed(error.localizedDescription) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.feed("HTTP \(http.statusCode)") }
        return try source.parse(data)
    }

    /// Downloads the release zip next to `bundle`, checks it against the published SHA-256, unpacks it and
    /// verifies the app inside. Returns the verified app, ready for `install`.
    public func stage(_ release: ReleaseInfo, for bundle: URL, identifier: String) async throws -> URL {
        let folder: URL
        do { folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundle, create: true) }
        catch { throw UpdateError.location("Updates cannot be staged next to the app: \(error.localizedDescription)") }
        do {
            var request = URLRequest(url: release.download)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let downloaded: URL, response: URLResponse
            do { (downloaded, response) = try await session.download(for: request) } catch { throw UpdateError.download(error.localizedDescription) }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.download("HTTP \(http.statusCode)") }
            let zip = folder.appendingPathComponent("update.zip")
            do { try FileManager.default.moveItem(at: downloaded, to: zip) } catch { throw UpdateError.download(error.localizedDescription) }
            guard try Self.sha256(of: zip) == release.sha256 else { throw UpdateError.checksum }
            let unpacked = folder.appendingPathComponent("unpacked", isDirectory: true)
            try Self.unpack(zip, to: unpacked)
            let apps = ((try? FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
            guard apps.count == 1, let app = apps.first else { throw UpdateError.invalidBundle("expected exactly one app in the download") }
            try Self.verify(app, identifier: identifier, version: release.version)
            return app
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Swaps the verified app into place. The running process keeps its already-loaded code until it relaunches.
    public func install(_ staged: URL, over bundle: URL) throws {
        do { _ = try FileManager.default.replaceItemAt(bundle, withItemAt: staged) }
        catch { throw UpdateError.install(error.localizedDescription) }
        try? FileManager.default.removeItem(at: staged.deletingLastPathComponent().deletingLastPathComponent())
    }

    /// Nil when `bundle` can be updated in place; otherwise the reason it cannot, in words for the Settings screen.
    public static func blocker(for bundle: URL) -> String? {
        guard bundle.pathExtension == "app" else { return "Updates apply to the packaged app, not a development build" }
        if bundle.path.contains("/AppTranslocation/") { return "macOS is running this copy from a temporary location. Move the app to Applications, open it from there, then update" }
        guard FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path), FileManager.default.isWritableFile(atPath: bundle.path)
        else { return "This copy cannot be replaced because its folder is not writable" }
        return nil
    }

    static func sha256(of file: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { throw UpdateError.download("file unreadable") }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func unpack(_ zip: URL, to folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw UpdateError.unpack }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.unpack }
    }

    /// The download must be this app (same bundle identifier), carry the advertised version, and have an intact
    /// code signature. Builds are ad-hoc signed, so the signature proves the bundle is unmodified since it was
    /// built, not who built it; authenticity rests on the HTTPS feed and its checksum.
    static func verify(_ app: URL, identifier: String, version: AppVersion) throws {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { throw UpdateError.invalidBundle("no Info.plist") }
        guard info["CFBundleIdentifier"] as? String == identifier else { throw UpdateError.invalidBundle("it is a different app") }
        guard let text = info["CFBundleShortVersionString"] as? String, let found = AppVersion(text), found == version
        else { throw UpdateError.invalidBundle("its version does not match the release") }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw UpdateError.invalidBundle("its code signature could not be read") }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { throw UpdateError.invalidBundle("its code signature is not intact") }
    }
}
