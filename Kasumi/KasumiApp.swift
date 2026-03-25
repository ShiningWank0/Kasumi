//
//  KasumiApp.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import Cocoa

@main
class KasumiApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
