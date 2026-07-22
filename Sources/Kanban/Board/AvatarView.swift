import AppKit
import SwiftUI

/// Loads and caches Jira user avatars. The Jira Basic-auth header is attached **only** for the Jira
/// host(s) — never for gravatar/CDN URLs — so credentials don't leak to third parties.
@MainActor
final class AvatarCache {
    static let shared = AvatarCache()
    private init() {}

    private var authHeader: String?
    private var jiraHosts: Set<String> = []
    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func configure(authHeader: String?, jiraBaseUrls: [String]) {
        self.authHeader = authHeader
        self.jiraHosts = Set(jiraBaseUrls.compactMap { URL(string: $0)?.host })
    }

    func image(for urlString: String) async -> NSImage? {
        if let img = cache[urlString] { return img }
        if let task = inFlight[urlString] { return await task.value }

        let header = (URL(string: urlString)?.host).map { jiraHosts.contains($0) } == true ? authHeader : nil
        let task = Task<NSImage?, Never> {
            guard let url = URL(string: urlString) else { return nil }
            var req = URLRequest(url: url)
            if let header { req.setValue(header, forHTTPHeaderField: "Authorization") }
            guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
            return NSImage(data: data)
        }
        inFlight[urlString] = task
        let img = await task.value
        inFlight.removeValue(forKey: urlString)
        if let img { cache[urlString] = img }
        return img
    }
}

/// A circular Jira avatar; falls back to a person glyph while loading or when there's no image.
struct AvatarView: View {
    let urlString: String?
    var size: CGFloat = 20
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: urlString) {
            image = nil
            guard let urlString else { return }
            image = await AvatarCache.shared.image(for: urlString)
        }
    }
}
