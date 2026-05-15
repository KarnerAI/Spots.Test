//
//  CachedAsyncImageTests.swift
//  Spots.TestTests
//
//  Issue 6 (6A) — covers AsyncImageLoader behavior used by CachedAsyncImage's
//  variant + fallback flow. Bugs here would either render broken images for
//  cold spots (variant missing, no fallback engaged) or cache 404s and stop
//  serving backfilled variants for ~1hr.
//
//  Drives the loader via a stub URLProtocol so tests are deterministic and
//  never touch the network. Each test seeds responses for specific URLs and
//  asserts that the loader returns the expected image (or nil) for each.
//

import Testing
import Foundation
import UIKit
@testable import Spots_Test

// MARK: - Stub URLProtocol

/// In-process URLProtocol that responds to registered URLs with canned bytes
/// + status. Cleaner than swizzling URLSession because URLSession picks up
/// any registered URLProtocol classes via configuration.
final class StubURLProtocol: URLProtocol {
    /// (url string) → (status code, response body bytes). Set by tests
    /// before running. Reset between tests.
    nonisolated(unsafe) static var responses: [String: (Int, Data)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let (status, body) = StubURLProtocol.responses[url.absoluteString] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { /* no-op */ }
}

// MARK: - Test fixtures

private func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    config.urlCache = nil
    return URLSession(configuration: config)
}

/// Tiny 1×1 red JPEG, encoded once at module load. Decodable by UIImage so
/// a 200 response with these bytes round-trips through the loader.
private let validJPEGBytes: Data = {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
    let img = renderer.image { ctx in
        UIColor.red.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return img.jpegData(compressionQuality: 0.9) ?? Data()
}()

// MARK: - Tests

struct AsyncImageLoaderTests {

    @Test func loadReturnsImageOn200() async throws {
        StubURLProtocol.responses = [
            "https://test.local/abc.jpg": (200, validJPEGBytes)
        ]
        defer { StubURLProtocol.responses = [:] }

        let session = makeStubSession()
        let url = URL(string: "https://test.local/abc.jpg")!
        let result = try await AsyncImageLoader.load(url: url, session: session)
        #expect(result != nil)
    }

    @Test func loadReturnsNilOn404() async throws {
        StubURLProtocol.responses = [
            "https://test.local/missing.jpg": (404, Data())
        ]
        defer { StubURLProtocol.responses = [:] }

        let session = makeStubSession()
        let url = URL(string: "https://test.local/missing.jpg")!
        let result = try await AsyncImageLoader.load(url: url, session: session)
        #expect(result == nil)
    }

    @Test func loadReturnsNilOnUndecodableBody() async throws {
        // 200 status but body isn't a valid image — should return nil so the
        // caller can fall back rather than render a broken Image.
        StubURLProtocol.responses = [
            "https://test.local/garbage.jpg": (200, Data([0x00, 0x01, 0x02, 0x03]))
        ]
        defer { StubURLProtocol.responses = [:] }

        let session = makeStubSession()
        let url = URL(string: "https://test.local/garbage.jpg")!
        let result = try await AsyncImageLoader.load(url: url, session: session)
        #expect(result == nil)
    }

    @Test func loadEvicts404FromURLCache() async throws {
        // Spin up a session with an URLCache so we can verify the eviction
        // path. Without eviction, URLSession could keep the 404 cached and
        // backfilled variants would stay invisible for the Cache-Control TTL.
        StubURLProtocol.responses = [
            "https://test.local/willvanish.jpg": (404, Data())
        ]
        defer { StubURLProtocol.responses = [:] }

        let cache = URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, diskPath: nil)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.urlCache = cache
        let session = URLSession(configuration: config)

        let url = URL(string: "https://test.local/willvanish.jpg")!
        let request = URLRequest(url: url)

        // Pre-seed a fake cached response to confirm removeCachedResponse fires.
        let fakeResponse = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!
        cache.storeCachedResponse(CachedURLResponse(response: fakeResponse, data: Data()), for: request)
        #expect(cache.cachedResponse(for: request) != nil)

        _ = try await AsyncImageLoader.load(url: url, session: session)

        // After a non-2xx load, the cached entry should be gone.
        #expect(cache.cachedResponse(for: request) == nil)
    }
}
