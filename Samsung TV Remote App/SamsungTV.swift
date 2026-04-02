//
//  SamsungTV.swift
//  Samsung TV Remote
//
//  Core model for Samsung TV connection and control
//  Uses WebSocket (port 8002) for remote keys, REST API (port 8001) for app launching
//

import Foundation
import Network
import Combine

class SamsungTV: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isPairing = false
    @Published var tvName: String = ""
    @Published var installedApps: [[String: Any]] = []
    @Published var debugLog: [String] = []
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    let tvIP: String
    private let tvPort: Int
    private var token: String?
    
    private let appName = "Samsung TV Remote"
    
    // Auto-reconnect state
    private var shouldBeConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?
    
    init(ip: String, port: Int = 8002) {
        self.tvIP = ip
        self.tvPort = port
        super.init()
        self.token = UserDefaults.standard.string(forKey: "samsung_tv_token_\(ip)")
    }
    
    deinit {
        stopTimers()
    }
    
    // MARK: - Debug Logging
    
    private func log(_ message: String) {
        print(message)
        DispatchQueue.main.async {
            self.debugLog.append("[\(Self.timestamp)] \(message)")
            if self.debugLog.count > 100 {
                self.debugLog.removeFirst()
            }
        }
    }
    
    private static var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    func clearLog() {
        DispatchQueue.main.async {
            self.debugLog.removeAll()
        }
    }
    
    // MARK: - Connection (WebSocket on port 8002)
    
    func connect() {
        guard webSocketTask == nil else {
            log("🔌 Already connected or connecting")
            return
        }
        
        shouldBeConnected = true
        
        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())
        
        var urlString = "wss://\(tvIP):\(tvPort)/api/v2/channels/samsung.remote.control"
        
        if let token = token {
            urlString += "?token=\(token)"
            log("🔑 Connecting with saved token")
        } else {
            let nameBase64 = appName.data(using: .utf8)?.base64EncodedString() ?? ""
            urlString += "?name=\(nameBase64)"
            log("🆕 First connection - pairing mode")
        }
        
        guard let url = URL(string: urlString) else {
            log("❌ Invalid URL: \(urlString)")
            return
        }
        
        log("🔌 Connecting to \(tvIP):\(tvPort)...")
        
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
        
        if token == nil {
            isPairing = true
        }
    }
    
    func disconnect() {
        shouldBeConnected = false
        reconnectAttempts = 0
        stopTimers()
        
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
        log("🔌 Disconnected (manual)")
    }
    
    // MARK: - Auto-Reconnect
    
    /// Called when the app returns to foreground
    func reconnectIfNeeded() {
        guard shouldBeConnected else {
            log("🔌 No reconnect needed - not previously connected")
            return
        }
        
        if isConnected {
            // Send a ping to check if connection is actually alive
            log("🔌 Checking connection health...")
            sendPing()
            return
        }
        
        log("🔌 App returned to foreground - reconnecting...")
        reconnectAttempts = 0
        attemptReconnect()
    }
    
    private func attemptReconnect() {
        guard shouldBeConnected else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            log("❌ Max reconnect attempts (\(maxReconnectAttempts)) reached")
            return
        }
        
        reconnectAttempts += 1
        log("🔄 Reconnect attempt \(reconnectAttempts)/\(maxReconnectAttempts)...")
        
        // Clean up old connection
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        
        // Small delay before reconnecting (exponential backoff)
        let delay = min(Double(reconnectAttempts) * 1.0, 5.0)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.shouldBeConnected else { return }
            self.connectInternal()
        }
    }
    
    /// Internal connect without resetting shouldBeConnected
    private func connectInternal() {
        guard webSocketTask == nil else { return }
        
        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())
        
        var urlString = "wss://\(tvIP):\(tvPort)/api/v2/channels/samsung.remote.control"
        
        if let token = token {
            urlString += "?token=\(token)"
        } else {
            let nameBase64 = appName.data(using: .utf8)?.base64EncodedString() ?? ""
            urlString += "?name=\(nameBase64)"
        }
        
        guard let url = URL(string: urlString) else {
            log("❌ Invalid URL")
            return
        }
        
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
        
        if token == nil {
            DispatchQueue.main.async {
                self.isPairing = true
            }
        }
    }
    
    // MARK: - Keep-Alive Ping
    
    private func startPingTimer() {
        stopPingTimer()
        DispatchQueue.main.async {
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func stopTimers() {
        stopPingTimer()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                self?.log("❌ Ping failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                }
                // Connection is dead, try to reconnect
                self?.attemptReconnect()
            } else {
                self?.log("💓 Ping OK")
            }
        }
    }
    
    /// Called when app goes to background - pause the ping timer
    func appDidEnterBackground() {
        log("🔌 App backgrounded - pausing keep-alive")
        stopPingTimer()
    }
    
    // MARK: - WebSocket Message Handling
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage()
                
            case .failure(let error):
                self?.log("❌ WebSocket error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                }
                // Auto-reconnect on unexpected disconnect
                self?.stopPingTimer()
                if self?.shouldBeConnected == true {
                    self?.log("🔄 Connection lost - will attempt reconnect...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self?.attemptReconnect()
                    }
                }
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        log("📥 Received: \(text.prefix(300))")
        
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else {
            return
        }
        
        log("📥 Event: \(event)")
        
        DispatchQueue.main.async {
            switch event {
            case "ms.channel.connect":
                self.isConnected = true
                self.isPairing = false
                self.reconnectAttempts = 0
                self.log("✅ Connected successfully!")
                
                // Start keep-alive ping
                self.startPingTimer()
                
                if let data = json["data"] as? [String: Any],
                   let token = data["token"] as? String {
                    self.token = token
                    UserDefaults.standard.set(token, forKey: "samsung_tv_token_\(self.tvIP)")
                    self.log("🔑 Token saved")
                }
                
            case "ms.channel.unauthorized":
                self.isPairing = true
                self.log("⚠️ Unauthorized - need to pair")
                
            default:
                break
            }
        }
    }
    
    // MARK: - Remote Control Keys (via WebSocket)
    
    func sendKey(_ key: String) {
        guard isConnected else {
            log("❌ Cannot send key - not connected")
            return
        }
        
        log("🔘 Sending key: \(key)")
        
        let message: [String: Any] = [
            "method": "ms.remote.control",
            "params": [
                "Cmd": "Click",
                "DataOfCmd": key,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey"
            ]
        ]
        
        sendWebSocketMessage(message)
    }
    
    private func sendWebSocketMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else {
            log("❌ Failed to serialize message")
            return
        }
        
        let wsMessage = URLSessionWebSocketTask.Message.string(text)
        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error = error {
                self?.log("❌ Send error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - App Launching (REST API on port 8001)
    
    /// Launch app via HTTP POST to the TV's REST API
    func launchApp(appId: String) {
        guard isConnected else {
            log("❌ Cannot launch app - not connected")
            return
        }
        
        log("🚀 Launching app: \(appId)")
        
        let urlString = "http://\(tvIP):8001/api/v2/applications/\(appId)"
        guard let url = URL(string: urlString) else {
            log("❌ Invalid URL: \(urlString)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        log("📤 POST → \(urlString)")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.log("❌ Launch error: \(error.localizedDescription)")
                    return
                }
                
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                
                switch status {
                case 200, 201:
                    self?.log("✅ App launched! (\(status))")
                case 404:
                    self?.log("❌ App not found (404) - may need to install from Samsung app store")
                case 403:
                    self?.log("❌ Forbidden (403) - TV may need re-pairing")
                case 503:
                    self?.log("⚠️ TV busy (503) - try again")
                default:
                    self?.log("⚠️ Status \(status): \(body.prefix(200))")
                }
            }
        }.resume()
    }
    
    // MARK: - Discover Installed Apps (REST API)
    
    /// Probe known app IDs to find which ones are installed on this TV
    func getInstalledApps() {
        guard isConnected else {
            log("❌ Cannot get apps - not connected")
            return
        }
        
        log("📱 Scanning for installed apps...")
        
        let knownApps: [(String, String)] = [
            ("Netflix", "3201907018807"),
            ("YouTube", "111299001912"),
            ("Prime Video", "3201910019365"),
            ("Hulu", "3201601007625"),
            ("Apple TV", "3201807016597"),
            ("Tubi", "3201504001965"),
            ("Max", "3202301029760"),
            ("HBO Max", "3201601007230"),
            ("Disney+", "3201901017640"),
            ("Disney+ v2", "3202009021709"),
            ("Peacock", "3202006020991"),
            ("Paramount+", "3201710014981"),
            ("Paramount+ v2", "3202110025305"),
            ("ESPN", "3201708014618"),
            ("Spotify", "3201606009684"),
            ("Apple Music", "3201908019041"),
            ("Pluto TV", "3201808016802"),
            ("Plex", "3201512006963"),
            ("Twitch", "3202203026841"),
            ("YouTube TV", "3201707014489"),
        ]
        
        var foundApps: [[String: Any]] = []
        let group = DispatchGroup()
        let lock = NSLock()
        
        for (name, appId) in knownApps {
            group.enter()
            
            let urlString = "http://\(tvIP):8001/api/v2/applications/\(appId)"
            guard let url = URL(string: urlString) else {
                group.leave()
                continue
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                defer { group.leave() }
                
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                
                if status == 200, let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let realName = json["name"] as? String ?? name
                    let appInfo: [String: Any] = [
                        "appId": appId,
                        "name": realName,
                        "running": json["running"] as? Bool ?? false,
                        "version": json["version"] as? String ?? ""
                    ]
                    lock.lock()
                    foundApps.append(appInfo)
                    lock.unlock()
                    self?.log("  ✅ \(realName) → \(appId)")
                }
            }.resume()
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.installedApps = foundApps.sorted {
                ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "")
            }
            self?.log("📱 Found \(foundApps.count) installed apps")
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension SamsungTV: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        log("🔌 WebSocket opened")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        log("🔌 WebSocket closed (code: \(closeCode.rawValue))")
        DispatchQueue.main.async {
            self.isConnected = false
        }
        stopPingTimer()
        
        // Auto-reconnect if we should still be connected
        if shouldBeConnected {
            log("🔄 Connection closed unexpectedly - will reconnect...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.attemptReconnect()
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
