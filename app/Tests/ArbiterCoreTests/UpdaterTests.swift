import XCTest
import CryptoKit
@testable import ArbiterCore

final class UpdaterTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("updater-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func testVersionsCompareNumerically() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("0.9.0")), try XCTUnwrap(AppVersion("v0.10.0")))
        XCTAssertEqual(AppVersion("1.2"), AppVersion("1.2.0"))
        XCTAssertEqual(AppVersion("v2.0.1")?.description, "2.0.1")
        for invalid in ["", "v", "1..2", "1.2-beta", "one", "1.2.3.4.5", "-1.0", "1234567.0"] { XCTAssertNil(AppVersion(invalid), invalid) }
    }

    func testFeedAcceptsOnlyAPublishedChecksummedDownloadFromTheExpectedPlace() throws {
        let source = UpdateSource(feed: URL(string: "https://example.invalid/latest")!, downloadPrefix: "https://example.invalid/releases/download/")
        let digest = "sha256:" + String(repeating: "ab", count: 32)
        func feed(tag: String = "v1.4.0", draft: Bool = false, prerelease: Bool = false, name: String = "App-1.4.0-macos-arm64.zip",
                  digest: String? = digest, url: String = "https://example.invalid/releases/download/v1.4.0/App-1.4.0-macos-arm64.zip") -> Data {
            var asset: [String: Any] = ["name": name, "size": 100, "browser_download_url": url]
            if let digest { asset["digest"] = digest }
            return try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft, "prerelease": prerelease, "assets": [asset]])
        }
        let release = try source.parse(feed())
        XCTAssertEqual(release.version, AppVersion("1.4.0"))
        XCTAssertEqual(release.sha256, String(repeating: "ab", count: 32))
        XCTAssertThrowsError(try source.parse(feed(draft: true)))
        XCTAssertThrowsError(try source.parse(feed(prerelease: true)))
        XCTAssertThrowsError(try source.parse(feed(tag: "nightly")))
        XCTAssertThrowsError(try source.parse(feed(name: "App-1.4.0-macos-x86_64.zip"))) { XCTAssertEqual($0 as? UpdateError, .noAsset) }
        XCTAssertThrowsError(try source.parse(feed(digest: nil)), "A download without a checksum is never offered")
        XCTAssertThrowsError(try source.parse(feed(digest: "md5:abcd")))
        XCTAssertThrowsError(try source.parse(feed(url: "https://elsewhere.invalid/App-1.4.0-macos-arm64.zip")), "Downloads from another location are refused")
        XCTAssertThrowsError(try source.parse(Data("not json".utf8)))
    }

    func testVerifiedUpdateReplacesTheInstalledApp() async throws {
        let installed = try makeApp(in: root.appendingPathComponent("Applications"), version: "1.0.0")
        let source = try publish(try makeApp(in: root.appendingPathComponent("build"), version: "1.1.0"), version: "1.1.0")
        let updater = Updater(source: source)
        let release = try await updater.latest()
        XCTAssertEqual(release.version, AppVersion("1.1.0"))
        let staged = try await updater.stage(release, for: installed, identifier: "test.arbiter.fixture")
        try await updater.install(staged, over: installed)
        XCTAssertEqual(version(of: installed), "1.1.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path), "Staging is cleaned up")
    }

    func testCorruptedDownloadIsDiscardedAndNothingIsInstalled() async throws {
        let installed = try makeApp(in: root.appendingPathComponent("Applications"), version: "1.0.0")
        let source = try publish(try makeApp(in: root.appendingPathComponent("build"), version: "1.1.0"), version: "1.1.0", corruptAfterDigest: true)
        let updater = Updater(source: source)
        let release = try await updater.latest()
        do { _ = try await updater.stage(release, for: installed, identifier: "test.arbiter.fixture"); XCTFail("A mismatched checksum must stop the update") }
        catch { XCTAssertEqual(error as? UpdateError, .checksum) }
        XCTAssertEqual(version(of: installed), "1.0.0")
    }

    func testDownloadIsRejectedWhenItIsAnotherAppTheWrongVersionOrModified() async throws {
        let installed = try makeApp(in: root.appendingPathComponent("Applications"), version: "1.0.0")
        let other = try publish(try makeApp(in: root.appendingPathComponent("other"), version: "1.1.0", identifier: "test.someone.else"), version: "1.1.0", name: "other")
        await assertRejected(other, installed, "different app")
        let mislabelled = try publish(try makeApp(in: root.appendingPathComponent("old"), version: "0.5.0"), version: "1.1.0", name: "old")
        await assertRejected(mislabelled, installed, "version does not match")
        let tampered = try makeApp(in: root.appendingPathComponent("tampered"), version: "1.1.0")
        try Data("changed after signing".utf8).write(to: tampered.appendingPathComponent("Contents/Resources/payload.txt"))
        await assertRejected(try publish(tampered, version: "1.1.0", name: "tampered"), installed, "signature")
        XCTAssertEqual(version(of: installed), "1.0.0")
    }

    func testAppsThatCannotBeReplacedSayWhy() {
        XCTAssertNotNil(Updater.blocker(for: URL(fileURLWithPath: "/tmp/.build/debug/arbiter-activity-monitor")))
        XCTAssertEqual(Updater.blocker(for: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/App.app"))?.contains("Applications"), true)
        XCTAssertNotNil(Updater.blocker(for: URL(fileURLWithPath: "/System/Applications/Calculator.app")))
    }

    private func assertRejected(_ source: UpdateSource, _ installed: URL, _ reason: String, line: UInt = #line) async {
        let updater = Updater(source: source)
        do {
            let release = try await updater.latest()
            _ = try await updater.stage(release, for: installed, identifier: "test.arbiter.fixture")
            XCTFail("Expected rejection: \(reason)", line: line)
        } catch let error as UpdateError {
            guard case .invalidBundle(let message) = error else { return XCTFail("Unexpected \(error)", line: line) }
            XCTAssertTrue(message.contains(reason), message, line: line)
        } catch { XCTFail("Unexpected \(error)", line: line) }
    }

    /// A minimal ad-hoc-signed app bundle, like the real build produces.
    private func makeApp(in folder: URL, version: String, identifier: String = "test.arbiter.fixture") throws -> URL {
        let app = folder.appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: app.appendingPathComponent("Contents/MacOS/fixture"))
        try Data("payload".utf8).write(to: app.appendingPathComponent("Contents/Resources/payload.txt"))
        let info: [String: Any] = ["CFBundleExecutable": "fixture", "CFBundleIdentifier": identifier, "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        return app
    }

    /// Zips the app and writes a release feed pointing at it, as files, so no network is involved.
    private func publish(_ app: URL, version: String, name: String = "release", corruptAfterDigest: Bool = false) throws -> UpdateSource {
        let folder = root.appendingPathComponent("published-" + name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent("Fixture-\(version)-macos-arm64.zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        let digest = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        if corruptAfterDigest { try (try Data(contentsOf: zip) + Data([0])).write(to: zip) }
        let asset: [String: Any] = ["name": zip.lastPathComponent, "size": 1000, "digest": "sha256:" + digest, "browser_download_url": zip.absoluteString]
        let feed = folder.appendingPathComponent("latest.json")
        try JSONSerialization.data(withJSONObject: ["tag_name": "v" + version, "draft": false, "prerelease": false, "assets": [asset]]).write(to: feed)
        return UpdateSource(feed: feed, downloadPrefix: "file://")
    }

    private func version(of app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(tool) failed")
    }
}
