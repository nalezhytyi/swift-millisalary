import Foundation
import Testing
@testable import MillisalaryCore

private func response(_ json: String) -> Data { Data(json.utf8) }

private let release = #"{"tag_name":"v0.2.0","html_url":"https://github.com/nalezhytyi/swift-millisalary/releases/tag/v0.2.0"}"#

@Test func versionsParseWithOrWithoutTheV() {
    #expect(ReleaseVersion("v1.2.3")?.description == "1.2.3")
    #expect(ReleaseVersion(" 0.10.0\n")?.description == "0.10.0")
    #expect(ReleaseVersion("1.2") == nil)
    #expect(ReleaseVersion("1.2.3-beta") == nil)
    #expect(ReleaseVersion("latest") == nil)
}

@Test func versionsCompareByNumberNotText() {
    #expect(ReleaseVersion("0.10.0")! > ReleaseVersion("0.9.9")!)
    #expect(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!)
    #expect(!(ReleaseVersion("0.1.0")! > ReleaseVersion("v0.1.0")!))
}

@Test func aNewerReleaseIsAvailable() {
    let check = GitHubReleases.check(status: 200, data: response(release), current: "0.1.0")
    #expect(check == .available(LatestRelease(
        version: ReleaseVersion("0.2.0")!,
        url: URL(string: "https://github.com/nalezhytyi/swift-millisalary/releases/tag/v0.2.0")!
    )))
}

@Test func theSameOrAnOlderReleaseIsCurrent() {
    #expect(GitHubReleases.check(status: 200, data: response(release), current: "0.2.0") == .current)
    #expect(GitHubReleases.check(status: 200, data: response(release), current: "1.0.0") == .current)
}

@Test func noReleaseYetIsCurrent() {
    #expect(GitHubReleases.check(status: 404, data: response(#"{"message":"Not Found"}"#), current: "0.1.0") == .current)
}

@Test(arguments: [
    #"{"tag_name":"nightly","html_url":"https://github.com/x/y/releases/tag/nightly"}"#,
    #"{"tag_name":"v0.2.0","html_url":"http://github.com/x/y/releases/tag/v0.2.0"}"#,
    #"{"tag_name":"v0.2.0"}"#,
    #"{"tag_name":2,"html_url":"https://github.com/x/y"}"#,
    #"not json"#,
])
func unusableResponsesFail(_ body: String) {
    #expect(GitHubReleases.check(status: 200, data: response(body), current: "0.1.0") == .failed)
}

@Test func serverErrorsFail() {
    #expect(GitHubReleases.check(status: 500, data: response(release), current: "0.1.0") == .failed)
    #expect(GitHubReleases.check(status: 403, data: response(release), current: "0.1.0") == .failed)
}

@Test func theLatestURLIsTheReposAPI() {
    #expect(GitHubReleases.latestURL(repo: "nalezhytyi/swift-millisalary").absoluteString
        == "https://api.github.com/repos/nalezhytyi/swift-millisalary/releases/latest")
}
