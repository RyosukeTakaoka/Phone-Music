import SwiftUI
import WebKit
import AVFoundation
import Combine  

// MARK: - Proximity / Audio Manager
final class ProximityAudioManager: ObservableObject {
    @Published var isNear: Bool = false

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(proximityChanged(_:)),
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )
        UIDevice.current.isProximityMonitoringEnabled = true
        configureAudio(forNear: UIDevice.current.proximityState)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.isProximityMonitoringEnabled = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    @objc private func proximityChanged(_ n: Notification) {
        let near = UIDevice.current.proximityState
        DispatchQueue.main.async {
            self.isNear = near
        }
        configureAudio(forNear: near)
    }

    private func configureAudio(forNear near: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            // 常に playAndRecord を使い、スピーカー/受話器のみ切り替え
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if near {
                try session.overrideOutputAudioPort(.none) // 受話器
            } else {
                try session.overrideOutputAudioPort(.speaker) // スピーカー
            }
        } catch {
            print("Audio session error: \(error)")
        }
    }
}

// MARK: - SwiftUI wrapper for WKWebView
struct WebView: UIViewRepresentable {
    @Binding var url: URL?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard let url = url else { return }
        // YouTube watch URL を embed に変換
        var finalURL = url
        if url.host?.contains("youtube.com") == true && url.path.contains("watch") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let v = queryItems.first(where: { $0.name == "v" })?.value {
                let embed = "https://www.youtube.com/embed/\(v)?playsinline=1"
                if let u = URL(string: embed) { finalURL = u }
            }
        }
        let request = URLRequest(url: finalURL)
        uiView.load(request)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        init(_ p: WebView) { parent = p }
    }
}

// MARK: - Main SwiftUI view
struct ContentView: View {
    @StateObject private var prox = ProximityAudioManager()
    @State private var urlString: String = "https://www.youtube.com"
    @State private var urlToLoad: URL? = URL(string: "https://www.youtube.com")

    var body: some View {
        VStack(spacing: 0) {
            // URL入力欄を極小化
            HStack(spacing: 4) {
                TextField("", text: $urlString, onCommit: loadInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(height: 28)
                    .disableAutocorrection(true)
                Button("Go") { loadInput() }
                    .font(.caption)
                    .frame(height: 28)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            // 近接センサー状態表示
            Text("近接: \(prox.isNear ? "耳元 (受話器)" : "離れている (スピーカー)")")
                .font(.subheadline)
                .foregroundColor(prox.isNear ? .green : .primary)
                .padding(.bottom, 2)

            // WebView を最大化
            WebView(url: $urlToLoad)
                .edgesIgnoringSafeArea(.all)
        }
    }

    private func loadInput() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: trimmed), u.scheme != nil {
            urlToLoad = u
            return
        }
        // 検索語の場合はYouTube検索URLにフォールバック
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let searchURL = URL(string: "https://www.youtube.com/results?search_query=\(q)") {
            urlToLoad = searchURL
        }
    }
}

