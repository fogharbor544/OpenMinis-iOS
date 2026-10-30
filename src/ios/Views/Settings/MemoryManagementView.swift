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
                Text("请在首页长按 Bot，选择编辑，再打开长期记忆。")
                NavigationLink("共享记忆") { BotMemoryView(owner: "shared", title: "共享记忆") }
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
