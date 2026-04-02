//
//  TVDiscoveryService.swift
//  Samsung TV Remote
//
//  Service for discovering Samsung TVs on local network using SSDP
//

import Foundation
import Network
import Combine

struct DiscoveredTV: Identifiable, Codable {
    let id: UUID
    let name: String
    let ip: String
    let model: String?
    let port: Int
    
    init(id: UUID = UUID(), name: String, ip: String, model: String?, port: Int) {
        self.id = id
        self.name = name
        self.ip = ip
        self.model = model
        self.port = port
    }
}

class TVDiscoveryService: ObservableObject {
    @Published var discoveredTVs: [DiscoveredTV] = []
    @Published var savedTVs: [DiscoveredTV] = []
    @Published var isSearching = false
    @Published var debugLog: [String] = []
    @Published var networkError: String?
    
    private var listener: NWListener?
    private var sendConnection: NWConnection?
    private let dispatchQueue = DispatchQueue(label: "com.samsungtv.discovery")
    private var networkMonitor: NWPathMonitor?
    
    // SSDP multicast address and port
    private let ssdpAddress = "239.255.255.250"
    private let ssdpPort: UInt16 = 1900
    private var discoveryTimer: DispatchWorkItem?
    
    private let savedTVsKey = "saved_tvs"
    
    init() {
        loadSavedTVs()
        checkNetworkStatus()
    }
    
    private func checkNetworkStatus() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.status == .satisfied {
                    if path.usesInterfaceType(.wifi) {
                        self?.networkError = nil
                        self?.log("✅ WiFi connection detected")
                    } else if path.usesInterfaceType(.cellular) {
                        self?.networkError = "Must be on WiFi, not cellular data"
                        self?.log("⚠️ Connected via cellular - WiFi required")
                    } else {
                        self?.networkError = "Unknown network type"
                        self?.log("⚠️ Unknown network interface type")
                    }
                } else {
                    self?.networkError = "No network connection"
                    self?.log("❌ No network connection available")
                }
                
                #if targetEnvironment(simulator)
                self?.log("⚠️ Running on SIMULATOR - multicast may not work!")
                self?.networkError = "Simulator detected - please test on a real device"
                #endif
            }
        }
        networkMonitor?.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    func startDiscovery() {
        log("🔍 Starting TV discovery...")
        
        // Check for simulator
        #if targetEnvironment(simulator)
        log("❌ RUNNING ON SIMULATOR - Network discovery won't work!")
        log("❌ Please run this app on a REAL iOS DEVICE")
        DispatchQueue.main.async {
            self.networkError = "⚠️ Simulator Detected: Multicast networking doesn't work in the iOS Simulator. Please test on a real device."
            self.isSearching = false
        }
        return
        #endif
        discoveredTVs.removeAll()
        isSearching = true
        
        // Cancel any existing timer
        discoveryTimer?.cancel()
        
        // Start listening for SSDP responses
        startListening()
        
        // Send discovery message after a brief delay to ensure listener is ready
        dispatchQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendDiscoveryMessage()
        }
        
        // Stop discovery after 10 seconds (increased from 5 for better discovery)
        let workItem = DispatchWorkItem { [weak self] in
            self?.stopDiscovery()
        }
        discoveryTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }
    
    private func startListening() {
        do {
            // Create UDP listener
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            params.acceptLocalOnly = false
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: ssdpPort)!)
            
            listener?.stateUpdateHandler = { [weak self] state in
                self?.log("👂 Listener state: \(state)")
                switch state {
                case .ready:
                    self?.log("✅ Listener ready on port \(self?.ssdpPort ?? 0)")
                case .failed(let error):
                    self?.log("❌ Listener failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.isSearching = false
                    }
                case .cancelled:
                    self?.log("🛑 Listener cancelled")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.log("📨 New connection received")
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: dispatchQueue)
            log("👂 Listener started successfully")
            
        } catch {
            log("❌ Failed to create listener: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isSearching = false
            }
        }
    }
    
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: dispatchQueue)
        receiveData(on: connection)
    }
    
    private func receiveData(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            if let error = error {
                self?.log("❌ Receive error: \(error.localizedDescription)")
                return
            }
            
            if let data = data, let response = String(data: data, encoding: .utf8) {
                self?.log("📩 Received response (\(data.count) bytes)")
                self?.parseDiscoveryResponse(response)
            }
            
            // Continue receiving
            if !isComplete {
                self?.receiveData(on: connection)
            }
        }
    }
    
    func stopDiscovery() {
        log("🛑 Stopping discovery...")
        discoveryTimer?.cancel()
        listener?.cancel()
        listener = nil
        sendConnection?.cancel()
        sendConnection = nil
        
        DispatchQueue.main.async {
            self.isSearching = false
            self.log("✅ Discovery stopped. Found \(self.discoveredTVs.count) TV(s)")
        }
    }
    
    private func sendDiscoveryMessage() {
        log("📤 Preparing to send discovery message...")
        
        // Create a separate connection for sending
        let host = NWEndpoint.Host(ssdpAddress)
        let port = NWEndpoint.Port(rawValue: ssdpPort)!
        
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        
        sendConnection = NWConnection(host: host, port: port, using: params)
        
        sendConnection?.stateUpdateHandler = { [weak self] state in
            self?.log("📡 Send connection state: \(state)")
            switch state {
            case .ready:
                self?.log("✅ Send connection ready, sending M-SEARCH...")
                self?.performSend()
            case .failed(let error):
                self?.log("❌ Send connection failed: \(error.localizedDescription)")
                
                // Check for specific errors
                if let posixError = error as? POSIXError {
                    if posixError.code == .ENETDOWN {
                        self?.log("❌ ERROR: Network is down!")
                        self?.log("💡 SOLUTION: Check these:")
                        self?.log("   1. Are you running on a REAL device (not simulator)?")
                        self?.log("   2. Is WiFi enabled and connected?")
                        self?.log("   3. Did you grant Local Network permission?")
                        self?.log("   4. Are you on the same WiFi as your TV?")
                        
                        DispatchQueue.main.async {
                            self?.networkError = "Network Error: Please check WiFi connection and permissions"
                        }
                    }
                }
            case .waiting(let error):
                // Only log persistent network down errors once
                if let posixError = error as? POSIXError, posixError.code == .ENETDOWN {
                    // Don't spam logs with repeated "network down" messages
                }
            default:
                break
            }
        }
        
        sendConnection?.start(queue: dispatchQueue)
    }
    
    private func performSend() {
        // Try multiple search targets for better compatibility
        let searchTargets = [
            "urn:samsung.com:device:RemoteControlReceiver:1",
            "ssdp:all",
            "upnp:rootdevice"
        ]
        
        for (index, target) in searchTargets.enumerated() {
            // Delay each send slightly to avoid overwhelming the network
            dispatchQueue.asyncAfter(deadline: .now() + Double(index) * 0.3) { [weak self] in
                self?.sendMSearch(target: target)
            }
        }
    }
    
    private func sendMSearch(target: String) {
        // Proper SSDP M-SEARCH format
        let message = "M-SEARCH * HTTP/1.1\r\n" +
                     "HOST: \(ssdpAddress):\(ssdpPort)\r\n" +
                     "MAN: \"ssdp:discover\"\r\n" +
                     "MX: 5\r\n" +
                     "ST: \(target)\r\n" +
                     "USER-AGENT: iOS/\(UIDevice.current.systemVersion) UPnP/1.1\r\n" +
                     "\r\n"
        
        guard let data = message.data(using: .utf8) else {
            log("❌ Failed to encode message")
            return
        }
        
        log("📤 Sending M-SEARCH for \(target) (\(data.count) bytes)")
        
        sendConnection?.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.log("❌ Send failed: \(error.localizedDescription)")
            } else {
                self?.log("✅ M-SEARCH sent successfully for \(target)")
            }
        })
    }
    
    private func parseDiscoveryResponse(_ response: String) {
        log("🔍 Parsing response...")
        log("Response preview: \(response.prefix(200))...")
        
        // Parse HTTP response headers
        let lines = response.components(separatedBy: "\r\n")
        var location: String?
        var server: String?
        
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.hasPrefix("location:") {
                location = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                log("📍 Found location: \(location ?? "nil")")
            } else if lowercased.hasPrefix("server:") {
                server = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                log("🖥️ Server: \(server ?? "nil")")
            }
        }
        
        guard let locationURL = location,
              let url = URL(string: locationURL),
              let host = url.host else {
            log("⚠️ Could not extract host from location")
            return
        }
        
        log("✅ Valid device found at \(host)")
        
        // Fetch device description
        fetchDeviceDescription(from: locationURL, ip: host)
    }
    
    private func fetchDeviceDescription(from urlString: String, ip: String) {
        log("📥 Fetching device description from \(urlString)")
        
        guard let url = URL(string: urlString) else {
            log("❌ Invalid URL: \(urlString)")
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.log("❌ Failed to fetch device description: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                self?.log("❌ No data received from device")
                return
            }
            
            guard let xml = String(data: data, encoding: .utf8) else {
                self?.log("❌ Could not decode XML")
                return
            }
            
            self?.log("📄 Received XML (\(xml.count) characters)")
            
            // Parse XML for device info
            let name = self?.extractXMLValue(from: xml, tag: "friendlyName") ?? "Samsung TV"
            let model = self?.extractXMLValue(from: xml, tag: "modelName")
            let manufacturer = self?.extractXMLValue(from: xml, tag: "manufacturer")
            
            self?.log("📺 Device info: \(name) | \(model ?? "unknown") | \(manufacturer ?? "unknown")")
            
            // Check if it's a Samsung device
            let isSamsung = manufacturer?.lowercased().contains("samsung") ?? 
                           model?.lowercased().contains("samsung") ?? 
                           name.lowercased().contains("samsung")
            
            if !isSamsung {
                self?.log("⚠️ Device is not a Samsung TV, skipping")
                return
            }
            
            let tv = DiscoveredTV(
                name: name,
                ip: ip,
                model: model,
                port: 8002
            )
            
            DispatchQueue.main.async {
                // Add if not already in list
                if !(self?.discoveredTVs.contains(where: { $0.ip == tv.ip }) ?? false) {
                    self?.discoveredTVs.append(tv)
                    self?.log("✅ Added TV to list: \(tv.name) at \(tv.ip)")
                } else {
                    self?.log("ℹ️ TV already in list: \(tv.ip)")
                }
            }
        }.resume()
    }
    
    private func extractXMLValue(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        
        return String(xml[range])
    }
    
    // MARK: - Debug Logging
    
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)"
        print(logMessage)
        
        DispatchQueue.main.async {
            self.debugLog.append(logMessage)
            // Keep only last 100 log entries
            if self.debugLog.count > 100 {
                self.debugLog.removeFirst()
            }
        }
    }
    
    func clearLog() {
        debugLog.removeAll()
    }
    
    // MARK: - Manual Entry
    
    // Manual IP entry fallback
    func addManualTV(ip: String, name: String = "Samsung TV") {
        log("➕ Manually adding TV: \(name) at \(ip)")
        
        let tv = DiscoveredTV(
            name: name,
            ip: ip,
            model: nil,
            port: 8002
        )
        
        if !discoveredTVs.contains(where: { $0.ip == tv.ip }) {
            discoveredTVs.append(tv)
            log("✅ Manual TV added successfully")
        } else {
            log("ℹ️ TV with this IP already exists")
        }
        
        // Also save to persistent storage
        saveTV(tv)
    }
    
    // MARK: - Saved TVs Management
    
    private func loadSavedTVs() {
        guard let data = UserDefaults.standard.data(forKey: savedTVsKey),
              let tvs = try? JSONDecoder().decode([DiscoveredTV].self, from: data) else {
            return
        }
        savedTVs = tvs
        log("📂 Loaded \(tvs.count) saved TV(s)")
    }
    
    func saveTV(_ tv: DiscoveredTV) {
        // Remove if already exists (by IP)
        savedTVs.removeAll(where: { $0.ip == tv.ip })
        
        // Add to beginning
        savedTVs.insert(tv, at: 0)
        
        // Persist to UserDefaults
        if let data = try? JSONEncoder().encode(savedTVs) {
            UserDefaults.standard.set(data, forKey: savedTVsKey)
            log("💾 Saved TV: \(tv.name) at \(tv.ip)")
        }
    }
    
    func removeSavedTV(_ tv: DiscoveredTV) {
        savedTVs.removeAll(where: { $0.id == tv.id })
        
        if let data = try? JSONEncoder().encode(savedTVs) {
            UserDefaults.standard.set(data, forKey: savedTVsKey)
            log("🗑️ Removed saved TV: \(tv.name)")
        }
    }
    
    func clearSavedTVs() {
        savedTVs.removeAll()
        UserDefaults.standard.removeObject(forKey: savedTVsKey)
        log("🗑️ Cleared all saved TVs")
    }
}
import UIKit // Needed for UIDevice

