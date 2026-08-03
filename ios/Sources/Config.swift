import Foundation

/// Configuration locale (issue du QR). Rien en dur.
final class Config: ObservableObject {
    @Published var isConfigured: Bool
    private let d = UserDefaults.standard

    init() { isConfigured = d.string(forKey: "url") != nil }

    var url: String  { d.string(forKey: "url")  ?? "" }
    var user: String { d.string(forKey: "user") ?? "" }
    var pass: String { d.string(forKey: "pass") ?? "" }
    var name: String { d.string(forKey: "name") ?? "SafeDesk" }

    func clear() {
        ["url", "user", "pass", "name"].forEach { d.removeObject(forKey: $0) }
        isConfigured = false
    }

    /// Accepte safedesk://connect?data=<b64url> ET https://...#<b64url>. Vrai si applique.
    func apply(code: String) -> Bool {
        let s = code.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: String?
        if s.hasPrefix("safedesk://") {
            if let comp = URLComponents(string: s) {
                payload = comp.queryItems?.first(where: { $0.name == "data" })?.value
            }
        } else if s.hasPrefix("https://") {
            payload = URL(string: s)?.fragment
        }
        guard var b64 = payload else { return false }
        b64 = b64.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let raw = Data(base64Encoded: b64),
              let any = try? JSONSerialization.jsonObject(with: raw),
              let obj = any as? [String: Any],
              let url = obj["url"] as? String,
              let user = obj["user"] as? String,
              let pass = obj["pass"] as? String,
              url.hasPrefix("https://")
        else { return false }
        d.set(url, forKey: "url")
        d.set(user, forKey: "user")
        d.set(pass, forKey: "pass")
        d.set(obj["name"] as? String ?? "SafeDesk", forKey: "name")
        isConfigured = true
        return true
    }
}