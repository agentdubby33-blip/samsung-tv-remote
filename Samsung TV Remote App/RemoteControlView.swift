//
//  RemoteControlView.swift
//  Samsung TV Remote
//
//  Main remote control interface
//  Design tokens from Figma — supports light & dark mode
//

import SwiftUI
import Speech
import UIKit

// MARK: - Theme Colors (from Figma tokens)

struct Theme {
    // Adapts to current color scheme
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.057, green: 0.057, blue: 0.057) : Color(red: 0.98, green: 0.98, blue: 0.99)
    }
    
    static func foreground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.96, green: 0.96, blue: 0.96) : Color(red: 0.012, green: 0.008, blue: 0.075)
    }
    
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.105, green: 0.105, blue: 0.105) : .white
    }
    
    static func cardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    
    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.17, green: 0.17, blue: 0.17) : Color(red: 0.925, green: 0.925, blue: 0.94)
    }
    
    static func mutedForeground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.55, green: 0.55, blue: 0.55) : Color(red: 0.44, green: 0.44, blue: 0.51)
    }
    
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.17, green: 0.17, blue: 0.17) : Color(red: 0.91, green: 0.92, blue: 0.94)
    }
    
    static let destructive = Color(red: 0.83, green: 0.09, blue: 0.24)
    static let blue = Color(red: 0.22, green: 0.45, blue: 0.95)
    
    static let radius: CGFloat = 10
    static let radiusLg: CGFloat = 14
}

// MARK: - Main View

struct RemoteControlView: View {
    @ObservedObject var tv: SamsungTV
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var showDebugPanel = false
    @StateObject private var voice = VoiceCommandService()
    @State private var showVoiceOverlay = false
    
    var body: some View {
        ZStack {
            Theme.background(colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                header
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        disconnectedBanner

                        powerButton
                        
                        CardSection(colorScheme: colorScheme) {
                            navigationPad
                        }
                        
                        CardSection(colorScheme: colorScheme) {
                            VStack(spacing: 20) {
                                volumeControls
                                
                                Divider()
                                    .overlay(Theme.cardBorder(colorScheme))
                                
                                channelControls
                                
                                Divider()
                                    .overlay(Theme.cardBorder(colorScheme))
                                
                                playbackControls
                            }
                        }
                        
                        streamingApps
                        
                        quickAccessButtons

                        numericKeypad

                        if showDebugPanel {
                            debugPanel
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }

            voiceOverlay
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.foreground(colorScheme))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Theme.muted(colorScheme))
                    )
            }
            
            Spacer()
            
            VStack(spacing: 5) {
                Text(tv.tvName.isEmpty ? "Samsung TV" : tv.tvName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.foreground(colorScheme))
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(tv.isConnected ? Color(red: 0.2, green: 0.78, blue: 0.35) : Theme.destructive)
                        .frame(width: 7, height: 7)
                    
                    Text(tv.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.mutedForeground(colorScheme))
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Voice button
                Button(action: {
                    if case .listening = voice.state {
                        voice.stopListening()
                        showVoiceOverlay = false
                    } else {
                        showVoiceOverlay = true
                        voice.startListening()
                    }
                }) {
                    Image(systemName: voiceMicIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(voiceMicColor)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(voiceMicBackground)
                        )
                }
                .disabled(!tv.isConnected)
                .onChange(of: voice.lastResult) { _, result in
                    guard let result else { return }
                    switch result {
                    case .key(let key):
                        tv.sendKey(key)
                    case .launchApp(let appId):
                        tv.launchApp(appId: appId)
                    case .unknown:
                        break
                    }
                    showVoiceOverlay = false
                }

                // Debug button
                Button(action: { showDebugPanel.toggle() }) {
                    Image(systemName: "ant")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(showDebugPanel ? .orange : Theme.mutedForeground(colorScheme))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Theme.muted(colorScheme))
                        )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.background(colorScheme))
    }
    
    // MARK: - Voice Helpers

    private var voiceMicIcon: String {
        switch voice.state {
        case .listening:  return "mic.fill"
        case .processing: return "waveform"
        default:          return "mic"
        }
    }

    private var voiceMicColor: Color {
        switch voice.state {
        case .listening:  return .white
        case .unauthorized, .error: return Theme.destructive
        default:          return Theme.mutedForeground(colorScheme)
        }
    }

    private var voiceMicBackground: Color {
        switch voice.state {
        case .listening:  return Theme.blue
        default:          return Theme.muted(colorScheme)
        }
    }

    // Floating voice feedback pill
    private var voiceOverlay: some View {
        VStack {
            Spacer()
            if showVoiceOverlay {
                HStack(spacing: 12) {
                    Image(systemName: voice.state == .listening ? "waveform" : "mic.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .symbolEffect(.variableColor, isActive: voice.state == .listening)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.state == .listening ? "Listening..." : "Voice")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        if !voice.feedbackMessage.isEmpty {
                            Text(voice.feedbackMessage)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Button(action: {
                        voice.stopListening()
                        showVoiceOverlay = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(voice.state == .listening ? Theme.blue : Color.gray.opacity(0.85))
                        .shadow(radius: 12, y: 4)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: showVoiceOverlay)
                .onChange(of: voice.state) { _, newState in
                    if case .idle = newState {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showVoiceOverlay = false
                        }
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Disconnected Banner

    @ViewBuilder
    private var disconnectedBanner: some View {
        if !tv.isConnected {
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.destructive)

                Text("Not connected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.foreground(colorScheme))

                Spacer()

                Button(action: { tv.connect() }) {
                    Text("Reconnect")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Theme.destructive)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .fill(Theme.destructive.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .stroke(Theme.destructive.opacity(0.25), lineWidth: 0.5)
                    )
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: 0.25), value: tv.isConnected)
        }
    }

    // MARK: - Power Button
    
    private var powerButton: some View {
        Button(action: { tv.sendKey("KEY_POWER") }) {
            Image(systemName: "power")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 72, height: 72)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.9, green: 0.2, blue: 0.25), Color(red: 0.75, green: 0.1, blue: 0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Theme.destructive.opacity(tv.isConnected ? 0.35 : 0), radius: 16, y: 4)
                )
        }
        .buttonStyle(RemotePress())
        .disabled(!tv.isConnected)
        .opacity(tv.isConnected ? 1 : 0.35)
    }
    
    // MARK: - Navigation Pad
    
    private var navigationPad: some View {
        VStack(spacing: 14) {
            SectionLabel("Navigation", colorScheme: colorScheme)
            
            VStack(spacing: 10) {
                DPadButton(icon: "chevron.up", colorScheme: colorScheme) {
                    tv.sendKey("KEY_UP")
                }
                .disabled(!tv.isConnected)
                
                HStack(spacing: 10) {
                    DPadButton(icon: "chevron.left", colorScheme: colorScheme) {
                        tv.sendKey("KEY_LEFT")
                    }
                    .disabled(!tv.isConnected)
                    
                    // OK button
                    Button(action: { tv.sendKey("KEY_ENTER") }) {
                        Text("OK")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 66, height: 66)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.blue, Theme.blue.opacity(0.8)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .shadow(color: Theme.blue.opacity(0.3), radius: 8, y: 3)
                            )
                    }
                    .buttonStyle(RemotePress())
                    .disabled(!tv.isConnected)
                    
                    DPadButton(icon: "chevron.right", colorScheme: colorScheme) {
                        tv.sendKey("KEY_RIGHT")
                    }
                    .disabled(!tv.isConnected)
                }
                
                DPadButton(icon: "chevron.down", colorScheme: colorScheme) {
                    tv.sendKey("KEY_DOWN")
                }
                .disabled(!tv.isConnected)
            }
            
            HStack(spacing: 12) {
                PillActionButton(icon: "arrow.uturn.backward", label: "Back", colorScheme: colorScheme) {
                    tv.sendKey("KEY_RETURN")
                }
                .disabled(!tv.isConnected)
                
                PillActionButton(icon: "house.fill", label: "Home", colorScheme: colorScheme) {
                    tv.sendKey("KEY_HOME")
                }
                .disabled(!tv.isConnected)
            }
            .padding(.top, 6)
        }
    }
    
    // MARK: - Volume Controls
    
    private var volumeControls: some View {
        VStack(spacing: 12) {
            SectionLabel("Volume", colorScheme: colorScheme)
            
            HStack(spacing: 12) {
                ControlButton(icon: "speaker.minus.fill", label: "Vol −", colorScheme: colorScheme) {
                    tv.sendKey("KEY_VOLDOWN")
                }
                .disabled(!tv.isConnected)
                
                ControlButton(icon: "speaker.slash.fill", label: "Mute", colorScheme: colorScheme) {
                    tv.sendKey("KEY_MUTE")
                }
                .disabled(!tv.isConnected)
                
                ControlButton(icon: "speaker.plus.fill", label: "Vol +", colorScheme: colorScheme) {
                    tv.sendKey("KEY_VOLUP")
                }
                .disabled(!tv.isConnected)
            }
        }
    }
    
    // MARK: - Channel Controls
    
    private var channelControls: some View {
        VStack(spacing: 12) {
            SectionLabel("Channel", colorScheme: colorScheme)
            
            HStack(spacing: 12) {
                ControlButton(icon: "chevron.up.circle", label: "CH +", colorScheme: colorScheme) {
                    tv.sendKey("KEY_CHUP")
                }
                .disabled(!tv.isConnected)
                
                ControlButton(icon: "arrow.clockwise", label: "Prev", colorScheme: colorScheme) {
                    tv.sendKey("KEY_PRECH")
                }
                .disabled(!tv.isConnected)
                
                ControlButton(icon: "chevron.down.circle", label: "CH −", colorScheme: colorScheme) {
                    tv.sendKey("KEY_CHDOWN")
                }
                .disabled(!tv.isConnected)
            }
        }
    }
    
    // MARK: - Playback Controls
    
    private var playbackControls: some View {
        VStack(spacing: 12) {
            SectionLabel("Playback", colorScheme: colorScheme)
            
            HStack(spacing: 12) {
                ControlButton(icon: "backward.fill", colorScheme: colorScheme) {
                    tv.sendKey("KEY_REWIND")
                }
                .disabled(!tv.isConnected)
                
                ControlButton(icon: "play.fill", colorScheme: colorScheme) {
                    tv.sendKey("KEY_PLAY")
                }
                .disabled(!tv.isConnected)
                
                ControlButton(icon: "pause.fill", colorScheme: colorScheme) {
                    tv.sendKey("KEY_PAUSE")
                }
                .disabled(!tv.isConnected)
                
                ControlButton(icon: "forward.fill", colorScheme: colorScheme) {
                    tv.sendKey("KEY_FF")
                }
                .disabled(!tv.isConnected)
            }
        }
    }
    
    // MARK: - Streaming Apps

    private var streamingApps: some View {
        VStack(spacing: 14) {
            HStack {
                SectionLabel("Streaming Apps", colorScheme: colorScheme)
                
                Spacer()
                
                Button(action: { tv.getInstalledApps() }) {
                    Text("Scan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Theme.blue.opacity(0.12))
                        )
                }
                .disabled(!tv.isConnected)
                .opacity(tv.isConnected ? 1 : 0.35)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                StreamingAppButton(name: "Netflix", icon: "play.rectangle.fill", color: .red, isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3201907018807")
                }
                StreamingAppButton(name: "YouTube", icon: "play.rectangle.fill", color: Color(red: 1.0, green: 0.0, blue: 0.0), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "111299001912")
                }
                StreamingAppButton(name: "YouTube TV", icon: "tv.fill", color: Color(red: 0.85, green: 0.1, blue: 0.1), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3201707014489")
                }
                StreamingAppButton(name: "Max", icon: "film.fill", color: Color(red: 0.0, green: 0.3, blue: 0.7), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3202301029760")
                }
                StreamingAppButton(name: "Prime Video", icon: "tv.fill", color: Color(red: 0.0, green: 0.6, blue: 0.9), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3201910019365")
                }
                StreamingAppButton(name: "Disney+", icon: "sparkles.tv.fill", color: Color(red: 0.07, green: 0.15, blue: 0.45), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3201901017640")
                }
                StreamingAppButton(name: "Hulu", icon: "play.rectangle.fill", color: Color(red: 0.1, green: 0.75, blue: 0.4), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3201601007625")
                }
                StreamingAppButton(name: "Peacock", icon: "play.rectangle.fill", color: Color(red: 0.15, green: 0.15, blue: 0.15), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3202006020991")
                }
                StreamingAppButton(name: "Paramount+", icon: "mountain.2.fill", color: Color(red: 0.0, green: 0.35, blue: 0.85), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3201710014981")
                }
                StreamingAppButton(name: "ESPN", icon: "sportscourt.fill", color: Color(red: 0.8, green: 0.1, blue: 0.1), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3201708014618")
                }
                StreamingAppButton(name: "Apple TV", icon: "appletv.fill", color: Color(red: 0.3, green: 0.3, blue: 0.35), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3201807016597")
                }
                StreamingAppButton(name: "Spotify", icon: "music.note", color: Color(red: 0.12, green: 0.84, blue: 0.38), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3201606009684")
                }
                StreamingAppButton(name: "Tubi", icon: "film.fill", color: Color(red: 0.98, green: 0.4, blue: 0.0), isConnected: tv.isConnected, colorScheme: colorScheme) {
                    tv.launchApp(appId: "3201504001965")
                }
            }
            
            // Discovered apps from Scan
            if !tv.installedApps.isEmpty {
                discoveredAppsSection
            }
        }
    }
    
    // MARK: - Discovered Apps
    
    private var discoveredAppsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Installed · \(tv.installedApps.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.top, 8)
            
            ForEach(Array(tv.installedApps.enumerated()), id: \.offset) { _, app in
                let appId = app["appId"] as? String ?? "?"
                let name = app["name"] as? String ?? "Unknown"
                let running = app["running"] as? Bool ?? false
                
                Button {
                    tv.launchApp(appId: appId)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.foreground(colorScheme))
                                if running {
                                    Text("RUNNING")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.green.opacity(0.15)))
                                }
                            }
                            Text(appId)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.orange.opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 16))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .fill(Theme.card(colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radius)
                                    .stroke(.orange.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                }
                .disabled(!tv.isConnected)
            }
        }
    }
    
    // MARK: - Quick Access
    
    private var quickAccessButtons: some View {
        VStack(spacing: 14) {
            SectionLabel("Quick Access", colorScheme: colorScheme)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                QuickButton(icon: "list.bullet", label: "Menu", colorScheme: colorScheme) {
                    tv.sendKey("KEY_MENU")
                }
                .disabled(!tv.isConnected)
                
                QuickButton(icon: "gearshape.fill", label: "Settings", colorScheme: colorScheme) {
                    tv.sendKey("KEY_TOOLS")
                }
                .disabled(!tv.isConnected)
                
                QuickButton(icon: "info.circle.fill", label: "Info", colorScheme: colorScheme) {
                    tv.sendKey("KEY_INFO")
                }
                .disabled(!tv.isConnected)
                
                QuickButton(icon: "rectangle.on.rectangle", label: "Source", colorScheme: colorScheme) {
                    tv.sendKey("KEY_SOURCE")
                }
                .disabled(!tv.isConnected)
                
                QuickButton(icon: "square.grid.2x2.fill", label: "Apps", colorScheme: colorScheme) {
                    tv.sendKey("KEY_APPS")
                }
                .disabled(!tv.isConnected)
                
                QuickButton(icon: "text.justify.leading", label: "Guide", colorScheme: colorScheme) {
                    tv.sendKey("KEY_GUIDE")
                }
                .disabled(!tv.isConnected)
            }
        }
    }
    
    // MARK: - Numeric Keypad

    private var numericKeypad: some View {
        CardSection(colorScheme: colorScheme) {
            VStack(spacing: 14) {
                SectionLabel("Keypad", colorScheme: colorScheme)
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 10) {
                            ForEach(1..<4, id: \.self) { col in
                                let num = row * 3 + col
                                ControlButton(label: "\(num)", colorScheme: colorScheme) {
                                    tv.sendKey("KEY_\(num)")
                                }
                                .disabled(!tv.isConnected)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        // Empty placeholder matching ControlButton width
                        Color.clear.frame(width: 48, height: 48)
                        ControlButton(label: "0", colorScheme: colorScheme) {
                            tv.sendKey("KEY_0")
                        }
                        .disabled(!tv.isConnected)
                        // Empty placeholder matching ControlButton width
                        Color.clear.frame(width: 48, height: 48)
                    }
                }
            }
        }
    }

    // MARK: - Debug Panel
    
    private var debugPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
                Text("Console")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange)
                
                Spacer()
                
                Button("Clear") { tv.clearLog() }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange.opacity(0.7))
                
                Button("Copy") {
                    UIPasteboard.general.string = tv.debugLog.joined(separator: "\n")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.orange.opacity(0.7))
                .padding(.leading, 8)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(tv.debugLog.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.4))
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxHeight: 300)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.03, green: 0.03, blue: 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.15), lineWidth: 0.5)
                    )
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusLg)
                .fill(colorScheme == .dark ? Color.black.opacity(0.5) : Color(red: 0.95, green: 0.93, blue: 0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusLg)
                        .stroke(Color.orange.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Section Label

struct SectionLabel: View {
    let text: String
    let colorScheme: ColorScheme
    
    init(_ text: String, colorScheme: ColorScheme) {
        self.text = text
        self.colorScheme = colorScheme
    }
    
    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.mutedForeground(colorScheme))
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
        }
    }
}

// MARK: - Card Section

struct CardSection<Content: View>: View {
    let colorScheme: ColorScheme
    let content: () -> Content
    
    init(colorScheme: ColorScheme, @ViewBuilder content: @escaping () -> Content) {
        self.colorScheme = colorScheme
        self.content = content
    }
    
    var body: some View {
        content()
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.card(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Theme.cardBorder(colorScheme), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 12, y: 4)
            )
    }
}

// MARK: - D-Pad Button

struct DPadButton: View {
    let icon: String
    let colorScheme: ColorScheme
    let action: () -> Void
    
    @Environment(\.isEnabled) var isEnabled
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(isEnabled ? Theme.foreground(colorScheme) : Theme.mutedForeground(colorScheme))
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(Theme.muted(colorScheme))
                        .overlay(
                            Circle()
                                .stroke(Theme.cardBorder(colorScheme), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(RemotePress())
        .opacity(isEnabled ? 1 : 0.35)
    }
}

// MARK: - Pill Action Button (Back/Home)

struct PillActionButton: View {
    let icon: String
    let label: String
    let colorScheme: ColorScheme
    let action: () -> Void
    
    @Environment(\.isEnabled) var isEnabled
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isEnabled ? Theme.foreground(colorScheme) : Theme.mutedForeground(colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Theme.muted(colorScheme))
                    .overlay(
                        Capsule()
                            .stroke(Theme.cardBorder(colorScheme), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(RemotePress())
        .opacity(isEnabled ? 1 : 0.35)
    }
}

// MARK: - Control Button (Volume/Channel/Playback)

struct ControlButton: View {
    var icon: String? = nil
    var label: String? = nil
    let colorScheme: ColorScheme
    let action: () -> Void

    // Legacy convenience init — keeps existing call-sites that pass icon as first positional arg
    init(icon: String, label: String? = nil, colorScheme: ColorScheme, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.colorScheme = colorScheme
        self.action = action
    }

    // Number-only init — no icon, just a label
    init(label: String, colorScheme: ColorScheme, action: @escaping () -> Void) {
        self.icon = nil
        self.label = label
        self.colorScheme = colorScheme
        self.action = action
    }

    @Environment(\.isEnabled) var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Theme.muted(colorScheme))
                        .overlay(
                            Circle()
                                .stroke(Theme.cardBorder(colorScheme), lineWidth: 0.5)
                        )
                        .frame(width: 48, height: 48)

                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(isEnabled ? Theme.foreground(colorScheme) : Theme.mutedForeground(colorScheme))
                    } else if let label = label {
                        Text(label)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isEnabled ? Theme.foreground(colorScheme) : Theme.mutedForeground(colorScheme))
                    }
                }
                .frame(width: 48, height: 48)

                if icon != nil, let label = label {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.mutedForeground(colorScheme))
                }
            }
        }
        .buttonStyle(RemotePress())
        .opacity(isEnabled ? 1 : 0.35)
    }
}

// MARK: - Quick Access Button

struct QuickButton: View {
    let icon: String
    let label: String
    let colorScheme: ColorScheme
    let action: () -> Void
    
    @Environment(\.isEnabled) var isEnabled
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isEnabled ? Theme.mutedForeground(colorScheme) : Theme.mutedForeground(colorScheme).opacity(0.4))
                    .frame(height: 22)
                
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.mutedForeground(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.card(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.cardBorder(colorScheme), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(RemotePress())
        .opacity(isEnabled ? 1 : 0.35)
    }
}

// MARK: - Streaming App Button

struct StreamingAppButton: View {
    let name: String
    let icon: String
    let color: Color
    let isConnected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(color)
                    )
                
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.foreground(colorScheme))
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.mutedForeground(colorScheme))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusLg)
                    .fill(Theme.card(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusLg)
                            .stroke(Theme.cardBorder(colorScheme), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04), radius: 4, y: 2)
            )
        }
        .buttonStyle(RemotePress())
        .disabled(!isConnected)
        .opacity(isConnected ? 1 : 0.35)
    }
}

// MARK: - Button Press Style

struct RemotePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }
}

// MARK: - Legacy compatibility

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct RemoteButton: View {
    let icon: String
    let size: CGFloat
    var label: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color(red: 0.2, green: 0.2, blue: 0.25)))
                if let label = label {
                    Text(label).font(.caption2).foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(isEnabled ? 1 : 0.4)
    }
}
