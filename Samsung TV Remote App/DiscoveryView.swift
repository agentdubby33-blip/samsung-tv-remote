//
//  DiscoveryView.swift
//  Samsung TV Remote
//
//  View for discovering and connecting to Samsung TVs
//

import SwiftUI
import Network
import UIKit

struct DiscoveryView: View {
    @StateObject private var discoveryService = TVDiscoveryService()
    @State private var selectedTV: SamsungTV?
    @State private var showRemote = false
    @State private var showManualEntry = false
    @State private var showDebugLog = false
    @State private var manualIP = ""
    @State private var manualName = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.05, blue: 0.1), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Simulator warning banner
                    #if targetEnvironment(simulator)
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Simulator Detected")
                                    .font(.headline)
                                
                                Text("TV discovery won't work in the simulator. Please test on a real device.")
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red, lineWidth: 2)
                                )
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    #endif
                    // Header with icon
                    VStack(spacing: 12) {
                        Image(systemName: "tv")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Samsung TV Remote")
                            .font(.title.bold())
                            .foregroundColor(.white)
                        
                        Text("Find your TV on the network")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                    
                    // Network error warning
                    if let error = discoveryService.networkError {
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title3)
                                
                                Text(error)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundColor(.white)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.orange, lineWidth: 2)
                                )
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    // Search button
                    Button(action: {
                        discoveryService.startDiscovery()
                    }) {
                        HStack {
                            if discoveryService.isSearching {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            
                            Text(discoveryService.isSearching ? "Searching..." : "Search for TVs")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue)
                        )
                    }
                    .disabled(discoveryService.isSearching)
                    .padding(.horizontal, 20)
                    
                    // Saved TVs section
                    if !discoveryService.savedTVs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "bookmark.fill")
                                    .foregroundColor(.blue)
                                Text("Saved TVs")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: {
                                    discoveryService.clearSavedTVs()
                                }) {
                                    Text("Clear All")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(discoveryService.savedTVs) { tv in
                                        SavedTVCard(tv: tv, onConnect: {
                                            connectToTV(ip: tv.ip, name: tv.name)
                                        }, onRemove: {
                                            discoveryService.removeSavedTV(tv)
                                        })
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    // Discovered TVs list
                    if !discoveryService.discoveredTVs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Found TVs")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                            
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(discoveryService.discoveredTVs) { tv in
                                        TVCard(tv: tv) {
                                            connectToTV(ip: tv.ip, name: tv.name)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    } else if !discoveryService.isSearching {
                        VStack(spacing: 16) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            
                            Text("No TVs found")
                                .font(.headline)
                                .foregroundColor(.gray)
                            
                            Text("Make sure your TV is on and connected to the same Wi-Fi network")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding(.top, 40)
                    }
                    
                    Spacer()
                    
                    // Debug log button
                    Button(action: {
                        showDebugLog = true
                    }) {
                        HStack {
                            Image(systemName: "ladybug")
                            Text("Debug Log")
                        }
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    }
                    .padding(.bottom, 8)
                    
                    // Manual entry button
                    Button(action: {
                        showManualEntry = true
                    }) {
                        HStack {
                            Image(systemName: "keyboard")
                            Text("Enter IP manually")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showRemote) {
            if let selectedTV = selectedTV {
                RemoteControlView(tv: selectedTV)
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntrySheet(
                ip: $manualIP,
                name: $manualName,
                onConnect: {
                    discoveryService.addManualTV(ip: manualIP, name: manualName.isEmpty ? "Samsung TV" : manualName)
                    connectToTV(ip: manualIP, name: manualName.isEmpty ? "Samsung TV" : manualName)
                    showManualEntry = false
                    manualIP = ""
                    manualName = ""
                }
            )
        }
        .sheet(isPresented: $showDebugLog) {
            DebugLogView(logs: discoveryService.debugLog, onClear: {
                discoveryService.clearLog()
            })
        }
        .preferredColorScheme(.dark)
    }
    
    private func connectToTV(ip: String, name: String) {
        let tv = SamsungTV(ip: ip)
        tv.tvName = name
        tv.connect()
        selectedTV = tv
        
        // Register with ActiveTVManager for auto-reconnect
        ActiveTVManager.shared.activeTV = tv
        
        // Save this TV for future use
        let discoveredTV = DiscoveredTV(
            name: name,
            ip: ip,
            model: nil,
            port: 8002
        )
        discoveryService.saveTV(discoveredTV)
        
        // Wait a moment for connection, then show remote
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showRemote = true
        }
    }
}

// MARK: - TV Card Component

struct TVCard: View {
    let tv: DiscoveredTV
    let onConnect: () -> Void
    
    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 16) {
                // TV icon
                Image(systemName: "tv")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.15))
                    )
                
                // TV info
                VStack(alignment: .leading, spacing: 4) {
                    Text(tv.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(tv.ip)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    if let model = tv.model {
                        Text(model)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Connect arrow
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
            )
        }
    }
}

// MARK: - Saved TV Card Component

struct SavedTVCard: View {
    let tv: DiscoveredTV
    let onConnect: () -> Void
    let onRemove: () -> Void
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: onConnect) {
                VStack(spacing: 12) {
                    // TV icon
                    Image(systemName: "tv.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                        )
                    
                    // TV info
                    VStack(spacing: 4) {
                        Text(tv.name)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(tv.ip)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 140)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                )
            }
            
            // Remove button
            Button(action: {
                showingDeleteConfirmation = true
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.title3)
            }
            .confirmationDialog("Remove this TV?", isPresented: $showingDeleteConfirmation) {
                Button("Remove", role: .destructive) {
                    onRemove()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
}

// MARK: - Manual Entry Sheet

struct ManualEntrySheet: View {
    @Binding var ip: String
    @Binding var name: String
    let onConnect: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Image(systemName: "network")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                        .padding(.top, 40)
                    
                    Text("Enter TV Details")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TV Name (Optional)")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            TextField("e.g., Living Room TV", text: $name)
                                .textFieldStyle(CustomTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("IP Address")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            TextField("e.g., 192.168.1.100", text: $ip)
                                .textFieldStyle(CustomTextFieldStyle())
                                .keyboardType(.decimalPad)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Button(action: onConnect) {
                        Text("Connect")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(ip.isEmpty ? Color.gray : Color.blue)
                            )
                    }
                    .disabled(ip.isEmpty)
                    .padding(.horizontal, 20)
                    
                    Text("You can find your TV's IP address in:\nSettings > General > Network > Network Status")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Custom Text Field Style

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
            )
            .foregroundColor(.white)
    }
}
// MARK: - Debug Log View

struct DebugLogView: View {
    let logs: [String]
    let onClear: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // System status info
                    SystemStatusView()
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.1, green: 0.1, blue: 0.15))
                    
                    Divider()
                    
                    // Log content
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(alignment: .leading, spacing: 8) {
                                if logs.isEmpty {
                                    Text("No logs yet. Start a TV discovery to see debug information.")
                                        .foregroundColor(.gray)
                                        .padding()
                                } else {
                                    ForEach(Array(logs.enumerated()), id: \.offset) { index, log in
                                        Text(log)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(colorForLog(log))
                                            .textSelection(.enabled)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 4)
                                            .id(index)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: logs.count) { oldValue, newValue in
                                // Auto-scroll to bottom when new logs arrive
                                if let lastIndex = logs.indices.last {
                                    withAnimation {
                                        proxy.scrollTo(lastIndex, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        onClear()
                    }
                    .foregroundColor(.orange)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func colorForLog(_ log: String) -> Color {
        if log.contains("❌") {
            return .red
        } else if log.contains("⚠️") {
            return .orange
        } else if log.contains("✅") {
            return .green
        } else if log.contains("🔍") || log.contains("📤") || log.contains("📥") {
            return .blue
        } else if log.contains("ℹ️") {
            return .gray
        } else {
            return .white
        }
    }
}

// MARK: - System Status View

struct SystemStatusView: View {
    @State private var isSimulator = false
    @State private var hasWiFi = false
    @State private var systemVersion = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System Status")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                statusIndicator(
                    icon: "iphone",
                    text: isSimulator ? "Simulator" : "Real Device",
                    isGood: !isSimulator
                )
                
                statusIndicator(
                    icon: "wifi",
                    text: hasWiFi ? "WiFi" : "No WiFi",
                    isGood: hasWiFi
                )
                
                Text("iOS \(systemVersion)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            checkSystemStatus()
        }
    }
    
    private func statusIndicator(icon: String, text: String, isGood: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(isGood ? .green : .red)
            Text(text)
                .font(.caption)
                .foregroundColor(isGood ? .green : .red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isGood ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        )
    }
    
    private func checkSystemStatus() {
        #if targetEnvironment(simulator)
        isSimulator = true
        #else
        isSimulator = false
        #endif
        
        systemVersion = UIDevice.current.systemVersion
        
        // Check WiFi
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                hasWiFi = path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
}
