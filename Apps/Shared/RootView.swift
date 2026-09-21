import OtohaChatKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ChatStore
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showingSettings = false
    @State private var query = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(query: $query, showingSettings: $showingSettings)
                .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 320)
        } detail: {
            if let conversation = store.conversation(store.selectedID) {
                ChatDetailView(conversationID: conversation.id)
                    .id(conversation.id)
            } else {
                EmptyCanvas()
            }
        }
        .tint(OtohaChatTheme.accent)
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
            .environmentObject(store)
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 460)
            #endif
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .safeAreaInset(edge: .top) {
            if let banner = store.banner, store.selectedID == nil {
                CopyableBanner(
                    text: banner,
                    systemImage: "info.circle",
                    tint: .orange,
                    font: .caption
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OtohaChatTheme.sidebar)
            }
        }
        .onChange(of: store.shouldOpenSettings) { _, open in
            if open {
                showingSettings = true
                store.shouldOpenSettings = false
            }
        }
        .alert(
            "Confirm note write",
            isPresented: Binding(
                get: { store.pendingMutation != nil },
                set: { if !$0 { store.respondToMutation(false) } }
            )
        ) {
            Button("Write note") { store.respondToMutation(true) }
            Button("Don't write", role: .cancel) { store.respondToMutation(false) }
            Button("Copy details") {
                Clipboard.copy(store.pendingMutation?.summary ?? "")
            }
        } message: {
            Text(store.pendingMutation?.summary ?? "")
                .textSelection(.enabled)
        }
    }
}

private struct EmptyCanvas: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("What should we do?")
                .font(.largeTitle.weight(.semibold))
                .textSelection(.enabled)
            Text("Start a chat from the sidebar.")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OtohaChatTheme.canvas)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: ChatStore
    @Binding var query: String
    @Binding var showingSettings: Bool
    @State private var renameID: UUID?
    @State private var renameText = ""

    private var filtered: [ChatSessionSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.conversations }
        return store.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.modelName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            newChatButton
            conversationList
            footer
        }
        .background(OtohaChatTheme.sidebar)
        .alert("Rename chat", isPresented: Binding(
            get: { renameID != nil },
            set: { if !$0 { renameID = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let renameID { store.rename(renameID, title: renameText) }
                renameID = nil
            }
            Button("Cancel", role: .cancel) { renameID = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("OtohaChat")
                .font(.headline)
            Spacer()
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var newChatButton: some View {
        Button {
            if store.createConversation() == nil {
                showingSettings = true
            }
        } label: {
            Label("New chat", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(OtohaChatTheme.chipFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityLabel("New chat")
    }

    private var conversationList: some View {
        List(filtered, selection: $store.selectedID) { conversation in
            ConversationRow(conversation: conversation)
                .tag(conversation.id)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button("Rename") {
                        renameID = conversation.id
                        renameText = conversation.title
                    }
                    Button("Copy title") {
                        Clipboard.copy(conversation.title)
                    }
                    Button("Copy model") {
                        Clipboard.copy(conversation.modelName)
                    }
                    Button("Delete", role: .destructive) {
                        Task { await store.delete(conversation.id) }
                    }
                }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, placement: .sidebar, prompt: "Search")
    }

    private var footer: some View {
        Button {
            showingSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.body)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(.subheadline.weight(.medium))
                    Text(footerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    private var footerSubtitle: String {
        if let conversation = store.conversation(store.selectedID),
           let profile = store.settings.profiles.first(where: { $0.id == conversation.profileID })
        {
            return profile.displayName
        }
        return store.preferredProfile()?.displayName ?? "Providers"
    }
}

private struct ConversationRow: View {
    let conversation: ChatSessionSummary

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .lineLimit(1)
                Text(conversation.modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if conversation.snapshot.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Generating")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conversation.title), \(conversation.modelName)")
    }
}
