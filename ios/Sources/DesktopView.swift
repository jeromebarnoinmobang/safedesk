import SwiftUI
import WebKit

/// Le bureau streame, plein ecran, auth automatique, ecran maintenu allume.
struct DesktopView: View {
    @EnvironmentObject var config: Config
    @State private var confirmQuit = false

    var body: some View {
        WebView(urlString: config.url, user: config.user, pass: config.pass)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .onLongPressGesture(minimumDuration: 1.2) { confirmQuit = true }
            .confirmationDialog("SafeDesk", isPresented: $confirmQuit) {
                Button("Oublier ce SafeDesk", role: .destructive) { config.clear() }
                Button("Rester", role: .cancel) {}
            }
    }
}

struct WebView: UIViewRepresentable {
    let urlString: String
    let user: String
    let pass: String

    func makeCoordinator() -> Coordinator { Coordinator(user: user, pass: pass) }

    func makeUIView(context: Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.allowsInlineMediaPlayback = true
        conf.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: conf)
        web.navigationDelegate = context.coordinator
        web.scrollView.bounces = false
        web.isOpaque = false
        web.backgroundColor = .black
        if let url = URL(string: urlString) { web.load(URLRequest(url: url)) }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let user: String
        let pass: String
        var tries = 0
        init(user: String, pass: String) { self.user = user; self.pass = pass }

        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let method = challenge.protectionSpace.authenticationMethod
            if method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodDefault {
                if tries < 3 {
                    tries += 1
                    completionHandler(.useCredential,
                                      URLCredential(user: user, password: pass, persistence: .forSession))
                    return
                }
            }
            completionHandler(.performDefaultHandling, nil)
        }
    }
}