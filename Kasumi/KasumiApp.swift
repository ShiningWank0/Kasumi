//
//  KasumiApp.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import SwiftUI

@main
struct KasumiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appDelegate.openDocumentAction()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}
