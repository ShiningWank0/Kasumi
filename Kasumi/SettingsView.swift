//
//  SettingsView.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("globalShortcutKeyCode") private var keyCode: Int = 0x28
    @AppStorage("globalShortcutDisplay") private var shortcutDisplay: String = "⌘⇧K"
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            ShortcutsSettingsView(shortcutDisplay: $shortcutDisplay)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
            
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("defaultExportFormat") private var exportFormat = "png"
    @AppStorage("jpegQuality") private var jpegQuality = 0.9
    
    var body: some View {
        Form {
            Section {
                Picker("Default Export Format:", selection: $exportFormat) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpg")
                    Text("TIFF").tag("tiff")
                }
                
                if exportFormat == "jpg" {
                    HStack {
                        Text("JPEG Quality:")
                        Slider(value: $jpegQuality, in: 0.1...1.0)
                        Text("\(Int(jpegQuality * 100))%")
                            .frame(width: 50)
                    }
                }
            } header: {
                Text("Export Settings")
            }
            
            Section {
                Toggle("Dockに表示しない（グローバルショートカットのみ）", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "hideDockIcon") },
                    set: { newValue in
                        UserDefaults.standard.set(newValue, forKey: "hideDockIcon")
                        if newValue {
                            NSApp.setActivationPolicy(.accessory)
                        } else {
                            NSApp.setActivationPolicy(.regular)
                        }
                    }
                ))
                Text("有効にすると、DockアイコンとメニューバーアプリUI が非表示になります。\nグローバルショートカット（⌘⇧K）でアプリを操作します。\n設定画面は次回起動時にショートカットから開けます。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("表示設定")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutsSettingsView: View {
    @Binding var shortcutDisplay: String
    @State private var isRecording = false

    // エディタショートカット（カスタマイズ可能）
    @AppStorage("shortcut_trim") private var trimKey = "c"
    @AppStorage("shortcut_mosaic") private var mosaicKey = "m"
    @AppStorage("shortcut_bgremoval") private var bgRemovalKey = "t"

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Global Shortcut:")
                        .frame(width: 150, alignment: .trailing)

                    ShortcutRecorderButton(
                        shortcutDisplay: $shortcutDisplay,
                        isRecording: $isRecording
                    )
                    .frame(width: 200, height: 32)
                }

                Text("This shortcut will open Kasumi with clipboard image or Finder-selected files.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 150)
            } header: {
                Text("Keyboard Shortcuts")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    EditableShortcutRow(label: "切り抜き", key: $trimKey)
                    EditableShortcutRow(label: "モザイク", key: $mosaicKey)
                    EditableShortcutRow(label: "背景透過", key: $bgRemovalKey)

                    Divider()

                    ShortcutRow(key: "⌘Z", description: "元に戻す / 背景透過取消")
                    ShortcutRow(key: "⌘⇧Z", description: "やり直し")
                    ShortcutRow(key: "⌘S", description: "保存")
                }
            } header: {
                Text("Editor Shortcuts")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct EditableShortcutRow: View {
    let label: String
    @Binding var key: String
    @State private var isEditing = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .trailing)

            Button(action: { startRecording() }) {
                Text(isEditing ? "キーを押してください..." : key.uppercased())
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 80, height: 28)
            }
            .buttonStyle(.bordered)
            .tint(isEditing ? .accentColor : nil)

            if isEditing {
                Button("取消") {
                    stopRecording()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }

            Spacer()
        }
    }

    private func startRecording() {
        isEditing = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                stopRecording()
                return nil
            }
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
               chars.first?.isLetter == true {
                key = String(chars.first!).lowercased()
                stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        isEditing = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

struct ShortcutRow: View {
    let key: String
    let description: String

    var body: some View {
        HStack {
            Text(description)
                .frame(width: 100, alignment: .trailing)

            Text(key)
                .font(.system(.body, design: .monospaced))
                .frame(width: 80, height: 28)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)

            Spacer()
        }
    }
}

struct ShortcutRecorderButton: View {
    @Binding var shortcutDisplay: String
    @Binding var isRecording: Bool
    
    var body: some View {
        Button(action: {
            isRecording.toggle()
        }) {
            HStack {
                Spacer()
                Text(isRecording ? "Press keys..." : shortcutDisplay)
                    .font(.system(.body, design: .monospaced))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .background(isRecording ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("Kasumi")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.vertical)
            
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(label: "License", value: "MIT License")
                InfoRow(label: "Privacy", value: "100% Local Processing")
                InfoRow(label: "Network", value: "No Internet Connection")
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("© 2026 Kasumi Contributors")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("View on GitHub", destination: URL(string: "https://github.com/yourusername/Kasumi")!)
                    .font(.caption)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
    }
}

#Preview("Settings - General") {
    GeneralSettingsView()
        .frame(width: 500, height: 400)
}

#Preview("Settings - Shortcuts") {
    ShortcutsSettingsView(shortcutDisplay: .constant("⌘⇧K"))
        .frame(width: 500, height: 400)
}

#Preview("Settings - About") {
    AboutSettingsView()
        .frame(width: 500, height: 400)
}

#Preview("Settings - Full") {
    SettingsView()
}
