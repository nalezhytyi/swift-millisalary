import Foundation

/// "1.2.3" or "v1.2.3": what release tags and the bundle version look like
public struct ReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ text: String) {
        guard let match = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .wholeMatch(of: /v?([0-9]+)\.([0-9]+)\.([0-9]+)/),
            let major = Int(match.1), let minor = Int(match.2), let patch = Int(match.3)
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

public struct LatestRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    /// Its page on GitHub, where the dmg is downloaded
    public let url: URL
}

public enum ReleaseCheck: Equatable, Sendable {
    case available(LatestRelease)
    case current
    case failed
}

/// The update check against the latest GitHub release (updates.ts in the
/// Electron app). The app isn't signed with a Developer ID, so it doesn't
/// replace itself: it only points to the release's page
public enum GitHubReleases {
    public static func latestURL(repo: String) -> URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }

    /// What a response says, for an app at `current` (fetchLatest)
    public static func check(status: Int, data: Data, current: String) -> ReleaseCheck {
        // GitHub answers 404 while the repository has no release yet
        if status == 404 { return .current }
        guard (200..<300).contains(status),
              let release = try? JSONDecoder().decode(Response.self, from: data),
              let tag = release.tag_name, let page = release.html_url,
              let version = ReleaseVersion(tag),
              let url = URL(string: page), url.scheme == "https"
        else { return .failed }

        guard let installed = ReleaseVersion(current), version > installed else { return .current }
        return .available(LatestRelease(version: version, url: url))
    }

    private struct Response: Decodable {
        let tag_name: String?
        let html_url: String?
    }
}
