//
//  MemoryManagementView.swift
//  MinisApp
//
//  Settings-level memory management: unified file list with edit/delete.
//

import SwiftUI

struct MemoryManagementView: View {
    @ObservedObject private var bots = BotWorkspaceStore.shared

    var body: some View {
        List {
            Section("Bot Memories") {
                ForEach(bots.data.bots) { bot in
                    NavigationLink(bot.name) { BotMemoryView(owner: "bot:\(bot.id)", title: bot.name) }
                }
                NavigationLink("Shared Materials") { BotMemoryView(owner: "shared", title: String(localized: "Shared Materials")) }
            }
            Section("Group Memories") {
                ForEach(bots.data.rooms) { room in
                    NavigationLink(room.name) { BotMemoryView(owner: "room:\(room.id)", title: room.name) }
                }
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
    }
}
