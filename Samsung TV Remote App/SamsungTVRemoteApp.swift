//
//  SamsungTVRemoteApp.swift
//  Samsung TV Remote
//
//  Main app entry point
//

import SwiftUI

@main
struct SamsungTVRemoteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            DiscoveryView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                // App returned to foreground — reconnect if needed
                ActiveTVManager.shared.reconnect()
            case .background:
                // App going to background — pause keep-alive to save battery
                ActiveTVManager.shared.pauseKeepAlive()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Active TV Manager
// Singleton that holds a reference to the currently active TV connection
// so the app entry point can trigger reconnects on foreground

class ActiveTVManager {
    static let shared = ActiveTVManager()
    
    weak var activeTV: SamsungTV?
    
    private init() {}
    
    func reconnect() {
        activeTV?.reconnectIfNeeded()
    }
    
    func pauseKeepAlive() {
        activeTV?.appDidEnterBackground()
    }
}
