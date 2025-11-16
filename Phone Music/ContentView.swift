import SwiftUI
import WebKit
import AVFoundation
import Combine
import SafariServices

// MARK: - 近接センサー / オーディオ管理
final class ProximityAudioManager: ObservableObject {
    @Published var isNear: Bool = false
    var pauseBehavior: PauseBehavior = .always

    enum PauseBehavior { case always, never, ask }
    var onPauseRequested: (() -> Void)? = nil

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
        DispatchQueue.main.async { self.isNear = near }
        configureAudio(forNear: near)
    }

    private func configureAudio(forNear near: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if near { try session.overrideOutputAudioPort(.none) }
            else { try session.overrideOutputAudioPort(.speaker); handlePauseBehavior() }
        } catch { print("Audio session error: \(error)") }
    }

    private func handlePauseBehavior() {
        guard let onPause = onPauseRequested else { return }
        switch pauseBehavior {
        case .always: onPause()
        case .never: break
        case .ask: onPause()
        }
    }
}

// MARK: - WKWebView ラッパー
struct WebView: UIViewRepresentable {
    @Binding var url: URL?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) { config.mediaTypesRequiringUserActionForPlayback = [] }
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard let url = url else { return }
        var finalURL = url

        if url.host?.contains("youtube.com") == true && url.path.contains("watch") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let v = queryItems.first(where: { $0.name == "v" })?.value {
                let embed = "https://www.youtube.com/embed/\(v)?playsinline=1"
                if let u = URL(string: embed) { finalURL = u }
            }
        }

        uiView.load(URLRequest(url: finalURL))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, WKNavigationDelegate { var parent: WebView; init(_ p: WebView) { parent = p } }
}

// MARK: - タブ
enum MediaTab { case youtube, spotify }

// MARK: - SafariViewController ラッパー
struct SafariWrapper: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safari = SFSafariViewController(url: url)
        safari.delegate = context.coordinator
        safari.modalPresentationStyle = .fullScreen
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDismiss() }
    }
}

// MARK: - メインビュー
struct ContentView: View {
    @StateObject private var prox = ProximityAudioManager()
    @State private var urlString: String = "https://www.youtube.com"
    @State private var urlToLoad: URL? = URL(string: "https://www.youtube.com")
    @State private var selectedTab: MediaTab = .youtube
    @State private var showSpotifySafari = false
    @State private var youtubeWebView: WKWebView? = nil

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea() // ステータスバーも含めて背景を白に

            VStack(spacing: 0) {
                // タブ
                HStack(spacing: 16) {
                    Button(action: { selectedTab = .youtube; loadYouTubeDefault() }) {
                        Text("YouTube")
                            .font(.headline)
                            .foregroundColor(selectedTab == .youtube ? .blue : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(selectedTab == .youtube ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                    }

                    Button(action: {
                        selectedTab = .spotify
                        showSpotifySafari = true
                    }) {
                        Text("Spotify")
                            .font(.headline)
                            .foregroundColor(selectedTab == .spotify ? .green : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(selectedTab == .spotify ? Color.green.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                // URL入力欄（YouTubeのみ）
                if selectedTab == .youtube {
                    HStack(spacing: 6) {
                        TextField("YouTube URL or search", text: $urlString, onCommit: loadInput)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                        Button(action: loadInput) {
                            Text("Go")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }

                // WKWebView（YouTubeのみ）
                if selectedTab == .youtube {
                    WebView(url: $urlToLoad)
                        .edgesIgnoringSafeArea(.all)
                }

                Spacer()
            }
        }
        .onAppear { loadYouTubeDefault() }
        .sheet(isPresented: $showSpotifySafari, onDismiss: {
            selectedTab = .youtube
            loadYouTubeDefault()
        }) {
            SafariWrapper(url: URL(string: "https://open.spotify.com")!) {
                showSpotifySafari = false
            }
        }
        .onReceive(prox.$isNear) { isNear in
            if !isNear {
                youtubeWebView?.evaluateJavaScript("document.querySelector('video')?.pause()")
            }
        }
    }

    private func loadYouTubeDefault() {
        urlString = "https://www.youtube.com"
        urlToLoad = URL(string: urlString)
    }

    private func loadInput() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let u = URL(string: trimmed), u.scheme != nil { urlToLoad = u; return }

        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if selectedTab == .youtube, let searchURL = URL(string: "https://www.youtube.com/results?search_query=\(q)") {
            urlToLoad = searchURL
        }
    }
}


// MARK: - App entry
@main
struct PhoneMusicApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
