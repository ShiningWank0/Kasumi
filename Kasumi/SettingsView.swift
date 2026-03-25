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
                Toggle("Show floating toolbar", isOn: .constant(true))
                Toggle("Auto-save on close", isOn: .constant(false))
            } header: {
                Text("Editor Preferences")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutsSettingsView: View {
    @Binding var shortcutDisplay: String
    @State private var isRecording = false
    
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
                    ShortcutRow(key: "C", description: "Trim tool")
                    ShortcutRow(key: "M", description: "Mosaic area tool")
                    ShortcutRow(key: "B", description: "Mosaic brush tool")
                    ShortcutRow(key: "T", description: "Background removal tool")
                    ShortcutRow(key: "⌘Z", description: "Undo")
                    ShortcutRow(key: "⌘⇧Z", description: "Redo")
                    ShortcutRow(key: "⌘S", description: "Save")
                    ShortcutRow(key: "⌘⇧S", description: "Save As...")
                }
            } header: {
                Text("Editor Shortcuts")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutRow: View {
    let key: String
    let description: String
    
    var body: some View {
        HStack {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .frame(width: 80, alignment: .trailing)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
            
            Text(description)
                .foregroundColor(.secondary)
            
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
