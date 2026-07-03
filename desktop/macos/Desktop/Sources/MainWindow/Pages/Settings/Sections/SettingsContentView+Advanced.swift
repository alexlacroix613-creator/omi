import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  func advancedCategoryHeader(title: String, icon: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: icon)
        .scaledFont(size: 16)
        .foregroundColor(OmiColors.purplePrimary)
      Text(title)
        .scaledFont(size: 18, weight: .semibold)
        .foregroundColor(OmiColors.textPrimary)
      Spacer()
    }
    .padding(.top, 16)
  }

  var advancedSection: some View {
    VStack(spacing: 24) {
      advancedCategoryHeader(title: "AI Setup", icon: "cpu")
      aiSetupSubsection
      advancedCategoryHeader(title: "Profile & Stats", icon: "brain")
      profileAndStatsSubsection
      advancedCategoryHeader(title: "Reset Onboarding", icon: "arrow.counterclockwise")
      resetOnboardingSubsection
      advancedCategoryHeader(title: "Goals", icon: "target")
      goalsSubsection
      advancedCategoryHeader(title: "Preferences", icon: "slider.horizontal.3")
      preferencesSubsection
      advancedCategoryHeader(title: "Troubleshooting", icon: "wrench.and.screwdriver")
      troubleshootingSubsection
      advancedCategoryHeader(title: "Developer API Keys", icon: "key")
      developerKeysSubsection

      advancedCategoryHeader(title: "Dev Tools", icon: "hammer")
      devToolsSubsection
    }
  }

  // MARK: - Dev Tools Subsection

  var devToolsSubsection: some View {
    VStack(spacing: 20) {
      settingsCard(settingId: "advanced.devtools.chatlab") {
        HStack(spacing: 12) {
          Image(systemName: "flask.fill")
            .scaledFont(size: 16)
            .foregroundColor(OmiColors.purplePrimary)
          VStack(alignment: .leading, spacing: 4) {
            Text("Chat Prompt Lab")
              .scaledFont(size: 15, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)
            Text("Iterate on chat system prompts with real questions, AI grading, and production ratings")
              .scaledFont(size: 12)
              .foregroundColor(OmiColors.textTertiary)
          }
          Spacer()
          Button("Open") {
            ChatLabWindowManager.shared.openWindow(chatProvider: chatProvider)
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 14)
          .padding(.vertical, 6)
          .background(OmiColors.purplePrimary)
          .foregroundColor(.white)
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      }
    }
  }

  // MARK: - Advanced Subsections

  var aiSetupSubsection: some View {
    VStack(spacing: 20) {
      settingsCard(settingId: "aichat.realtimevoice") {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Image(systemName: "waveform")
              .scaledFont(size: 16)
              .foregroundColor(OmiColors.textTertiary)

            Text("Voice Model")
              .scaledFont(size: 15, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()

            Picker("", selection: $realtimeOmniProvider) {
              ForEach(RealtimeOmniProvider.allCases, id: \.rawValue) { p in
                Text(p.displayName).tag(p.rawValue)
              }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
            .onChange(of: realtimeOmniProvider) { _, newValue in
              if newValue == RealtimeOmniProvider.auto.rawValue {
                AutoModelSelector.shared.refreshIfStale()
              }
              // The picker writes @AppStorage directly (bypassing the RealtimeOmniSettings
              // setter), so post the change ourselves — this is what re-warms the realtime
              // hub on the newly selected provider (and is a no-op for unchanged providers).
              NotificationCenter.default.post(name: .realtimeOmniSettingsDidChange, object: nil)
            }
          }

          if let p = RealtimeOmniProvider(rawValue: realtimeOmniProvider), p == .auto {
            Text("\(p.subtitle) · currently \(RealtimeOmniSettings.shared.effectiveProvider.displayName)")
              .scaledFont(size: 12)
              .foregroundColor(OmiColors.textTertiary)
          } else if let p = RealtimeOmniProvider(rawValue: realtimeOmniProvider) {
            Text(p.subtitle)
              .scaledFont(size: 12)
              .foregroundColor(OmiColors.textTertiary)
          }

          Divider()

          realtimeVoiceKeyField

          Divider()

          voiceEngineChatGPTCascadeRow
        }
      }

      voiceTranscriptionCard

      aiAccountsCard

      openRouterKeyCard(settingId: "aichat.openrouter")

      settingsCard(settingId: "aichat.provider") {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Image(systemName: "cpu")
              .scaledFont(size: 16)
              .foregroundColor(OmiColors.textTertiary)

            Text("AI Provider")
              .scaledFont(size: 15, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()

            Picker("", selection: $chatBridgeMode) {
              ForEach(AIProvider.all) { provider in
                Text(provider.displayName).tag(provider.bridgeModeRawValue)
              }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
            .onChange(of: chatBridgeMode) { _, newMode in
              if let mode = ChatProvider.BridgeMode(rawValue: newMode) {
                Task {
                  await chatProvider?.switchBridgeMode(to: mode)
                }
              }
            }
          }

          if let provider = AIProvider.from(bridgeMode: chatBridgeMode) {
            if let url = provider.attributionURL {
              Link(destination: url) {
                Text("\(provider.tagline) · \(url.host ?? "")")
                  .scaledFont(size: 12)
                  .foregroundColor(OmiColors.textTertiary)
              }
            } else {
              Text(provider.tagline)
                .scaledFont(size: 12)
                .foregroundColor(OmiColors.textTertiary)
            }
          }

          if chatBridgeMode == "claudeCode" && chatProvider?.isClaudeConnected == true {
            Divider()

            HStack {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .scaledFont(size: 12)
              Text("Connected to Claude")
                .scaledFont(size: 12)
                .foregroundColor(OmiColors.textSecondary)

              Spacer()

              Button("Disconnect") {
                Task {
                  await chatProvider?.disconnectClaude()
                }
              }
              .buttonStyle(.plain)
              .scaledFont(size: 12, weight: .medium)
              .foregroundColor(.red)
            }
          }
        }
      }

      settingsCard(settingId: "aichat.workspace") {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Image(systemName: "folder")
              .scaledFont(size: 16)
              .foregroundColor(OmiColors.textTertiary)

            Text("Workspace")
              .scaledFont(size: 15, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()

            Button("Browse...") {
              let panel = NSOpenPanel()
              panel.canChooseFiles = false
              panel.canChooseDirectories = true
              panel.allowsMultipleSelection = false
              panel.message = "Select a project directory"
              if panel.runModal() == .OK, let url = panel.url {
                aiChatWorkingDirectory = url.path
                chatProvider?.aiChatWorkingDirectory = url.path
                Task { await chatProvider?.discoverClaudeConfig() }
                if chatProvider?.workingDirectory == nil {
                  chatProvider?.workingDirectory = url.path
                }
              }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if !aiChatWorkingDirectory.isEmpty {
              Button("Clear") {
                aiChatWorkingDirectory = ""
                chatProvider?.aiChatWorkingDirectory = ""
                Task { await chatProvider?.discoverClaudeConfig() }
                chatProvider?.workingDirectory = nil
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }

          if !aiChatWorkingDirectory.isEmpty {
            Text(aiChatWorkingDirectory)
              .scaledFont(size: 12)
              .foregroundColor(OmiColors.textTertiary)
              .lineLimit(1)
              .truncationMode(.middle)
          } else {
            Text("No workspace set. Choose a project directory for desktop chat context.")
              .scaledFont(size: 12)
              .foregroundColor(OmiColors.textTertiary)
          }
        }
      }

      settingsCard(settingId: "aichat.browserextension") {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Image(systemName: "globe")
              .scaledFont(size: 16)
              .foregroundColor(OmiColors.textTertiary)

            Text("Browser Extension")
              .scaledFont(size: 15, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()

            if !playwrightExtensionToken.isEmpty {
              HStack(spacing: 4) {
                Circle()
                  .fill(Color.green)
                  .frame(width: 6, height: 6)
                Text("Connected")
                  .scaledFont(size: 11)
                  .foregroundColor(OmiColors.textTertiary)
              }
            }

            Toggle("", isOn: $playwrightUseExtension)
              .toggleStyle(.switch)
              .controlSize(.small)
              .labelsHidden()
          }

          Text("Lets the AI use your Chrome browser with all your logged-in sessions.")
            .scaledFont(size: 12)
            .foregroundColor(OmiColors.textTertiary)

          if playwrightUseExtension {
            if playwrightExtensionToken.isEmpty {
              Button(action: {
                showBrowserSetup = true
              }) {
                HStack(spacing: 6) {
                  Image(systemName: "wrench.and.screwdriver")
                    .scaledFont(size: 12)
                  Text("Set Up")
                    .scaledFont(size: 13, weight: .medium)
                }
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
            } else {
              HStack(spacing: 8) {
                Text("Token")
                  .scaledFont(size: 12)
                  .foregroundColor(OmiColors.textTertiary)

                Text(String(playwrightExtensionToken.prefix(8)) + "...")
                  .scaledFont(size: 12, weight: .medium)
                  .foregroundColor(OmiColors.textPrimary)
                  .font(.system(.body, design: .monospaced))

                Spacer()

                Button(action: {
                  showBrowserSetup = true
                }) {
                  HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                      .scaledFont(size: 11)
                    Text("Reconfigure")
                      .scaledFont(size: 12)
                  }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                  playwrightExtensionToken = ""
                  UserDefaults.standard.set("", forKey: "playwrightExtensionToken")
                }) {
                  HStack(spacing: 4) {
                    Image(systemName: "xmark")
                      .scaledFont(size: 11)
                    Text("Reset")
                      .scaledFont(size: 12)
                  }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
              }
            }
          }
        }
      }

      settingsCard(settingId: "aichat.devmode") {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Image(systemName: "hammer")
              .scaledFont(size: 16)
              .foregroundColor(OmiColors.textTertiary)

            Text("Dev Mode")
              .scaledFont(size: 15, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()

            Toggle("", isOn: $devModeEnabled)
              .toggleStyle(.switch)
              .controlSize(.small)
              .labelsHidden()
              .onChange(of: devModeEnabled) { _, newValue in
                AnalyticsManager.shared.settingToggled(setting: "dev_mode", enabled: newValue)
              }
          }

          Text("Let the AI modify the app's source code, rebuild it, and add custom features.")
            .scaledFont(size: 12)
            .foregroundColor(OmiColors.textTertiary)
        }
      }
    }
  }

  var profileAndStatsSubsection: some View {
    VStack(spacing: 20) {
      settingsCard(settingId: "advanced.profileandstats") {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            Image(systemName: showProfileAndStats ? "eye.slash" : "eye")
              .scaledFont(size: 15)
              .foregroundColor(OmiColors.purplePrimary)

            VStack(alignment: .leading, spacing: 4) {
              Text("Profile and Stats")
                .scaledFont(size: 15, weight: .semibold)
                .foregroundColor(OmiColors.textPrimary)
              Text("Keep the generated profile and usage stats hidden until you need them.")
                .scaledFont(size: 12)
                .foregroundColor(OmiColors.textTertiary)
            }

            Spacer()

            Button(showProfileAndStats ? "Hide" : "Show") {
              withAnimation(.easeInOut(duration: 0.2)) {
                showProfileAndStats.toggle()
              }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
      }

      if showProfileAndStats {
        aiUserProfileSubsection
        statsSubsection
      }
    }
  }

  var aiUserProfileSubsection: some View {
    VStack(spacing: 20) {
      settingsCard(settingId: "advanced.aiuserprofile") {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 10) {
            Image(systemName: "brain")
              .scaledFont(size: 16)
              .foregroundColor(OmiColors.purplePrimary)

            Text("AI User Profile")
              .scaledFont(size: 15, weight: .medium)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()

            if isGeneratingAIProfile {
              ProgressView()
                .controlSize(.small)
            } else {
              Button(action: {
                regenerateAIProfile()
              }) {
                Text(aiProfileText == nil ? "Generate Now" : "Regenerate")
                  .scaledFont(size: 12)
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }

          Divider()
            .background(OmiColors.backgroundQuaternary)

          if let text = aiProfileText {
            if isEditingAIProfile {
              TextEditor(text: $aiProfileEditText)
                .scaledFont(size: 13, design: .monospaced)
                .foregroundColor(OmiColors.textSecondary)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 200)

              HStack {
                Button("Cancel") {
                  isEditingAIProfile = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save") {
                  if let id = aiProfileId {
                    Task {
                      let success = await AIUserProfileService.shared.updateProfileText(
                        id: id, newText: aiProfileEditText
                      )
                      if success {
                        aiProfileText = aiProfileEditText
                      }
                      isEditingAIProfile = false
                    }
                  }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()
              }
            } else {
              ScrollView {
                Text(text)
                  .scaledFont(size: 13, design: .monospaced)
                  .foregroundColor(OmiColors.textSecondary)
                  .textSelection(.enabled)
                  .if_available_writingToolsNone()
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .frame(maxHeight: 200)

              HStack {
                if let date = aiProfileGeneratedAt {
                  Text("Last updated: \(date.formatted(.relative(presentation: .named)))")
                    .scaledFont(size: 12)
                    .foregroundColor(OmiColors.textTertiary)
                }

                Spacer()

                if aiProfileDataSourcesUsed > 0 {
                  Text("Data sources: \(aiProfileDataSourcesUsed) items")
                    .scaledFont(size: 12)
                    .foregroundColor(OmiColors.textTertiary)
                }

                Button(action: {
                  aiProfileEditText = text
                  isEditingAIProfile = true
                }) {
                  Image(systemName: "pencil")
                    .scaledFont(size: 11)
                }
                .buttonStyle(.borderless)
                .help("Edit profile")

                Button(action: {
                  deleteCurrentAIProfile()
                }) {
                  Image(systemName: "trash")
                    .scaledFont(size: 11)
                    .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .help("Delete this profile")
              }
            }
          } else if !isGeneratingAIProfile {
            Text(
              "Your AI user profile will be generated automatically on next launch, or click \"Generate Now\" to create it now."
            )
            .scaledFont(size: 13)
            .foregroundColor(OmiColors.textTertiary)
          } else {
            HStack {
              Spacer()
              VStack(spacing: 8) {
                ProgressView()
                Text("Generating profile...")
                  .scaledFont(size: 13)
                  .foregroundColor(OmiColors.textTertiary)
              }
              Spacer()
            }
            .padding(.vertical, 20)
          }
        }
      }
    }
    .task {
      // Try loading immediately (covers all restarts after first generation)
      if let profile = await AIUserProfileService.shared.getLatestProfile() {
        aiProfileId = profile.id
        aiProfileText = profile.profileText
        aiProfileGeneratedAt = profile.generatedAt
        aiProfileDataSourcesUsed = profile.dataSourcesUsed
        return
      }
      // No profile yet — first-ever generation may be in progress, poll briefly
      for _ in 0..<6 {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if let profile = await AIUserProfileService.shared.getLatestProfile() {
          aiProfileId = profile.id
          aiProfileText = profile.profileText
          aiProfileGeneratedAt = profile.generatedAt
          aiProfileDataSourcesUsed = profile.dataSourcesUsed
          return
        }
      }
    }
  }

  var statsSubsection: some View {
    VStack(spacing: 20) {
      settingsCard(settingId: "advanced.stats") {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 10) {
            Image(systemName: "chart.bar")
              .scaledFont(size: 16)
              .foregroundColor(OmiColors.purplePrimary)

            Text("Your Stats")
              .scaledFont(size: 15, weight: .medium)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()
          }

          Divider()
            .background(OmiColors.backgroundQuaternary)

          if let stats = advancedStats {
            statRow(label: "Conversations", value: stats.conversations)
            statRow(label: "Apps Installed", value: stats.appsInstalled)
            if isLoadingChatMessages {
              HStack {
                Text("AI Chat Messages")
                  .scaledFont(size: 14)
                  .foregroundColor(OmiColors.textSecondary)
                Spacer()
                ProgressView()
                  .controlSize(.mini)
              }
            } else if let count = chatMessageCount {
              statRow(label: "AI Chat Messages", value: count)
            }
            statRow(label: "Screenshots", value: stats.screenshotsTotal)
            statRow(label: "Focus Sessions", value: stats.focusSessions)
            statRow(label: "Tasks (To Do)", value: stats.tasksTodo)
            statRow(label: "Tasks (Done)", value: stats.tasksDone)
            statRow(label: "Tasks (Removed)", value: stats.tasksDeleted)
            statRow(label: "Goals", value: stats.goalsCount)
            statRow(label: "Memories", value: stats.memoriesTotal)
          } else if isLoadingStats {
            statRowLoading(label: "Conversations")
            statRowLoading(label: "Apps Installed")
            statRowLoading(label: "AI Chat Messages")
            statRowLoading(label: "Screenshots")
            statRowLoading(label: "Focus Sessions")
            statRowLoading(label: "Tasks (To Do)")
            statRowLoading(label: "Tasks (Done)")
            statRowLoading(label: "Tasks (Removed)")
            statRowLoading(label: "Goals")
            statRowLoading(label: "Memories")
          } else {
            Text("Unable to load stats")
              .scaledFont(size: 13)
              .foregroundColor(OmiColors.textTertiary)
          }
        }
      }
    }
    .task {
      await loadAdvancedStats()
    }
    .task {
      await loadChatMessageCount()
    }
  }

  var featureTiersSubsection: some View {
    VStack(spacing: 20) {
      settingsCard(settingId: "advanced.featuretiers") {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 10) {
            Image(systemName: "lock.shield")
              .scaledFont(size: 16)
              .foregroundColor(OmiColors.purplePrimary)

            Text("Feature Tiers")
              .scaledFont(size: 15, weight: .medium)
              .foregroundColor(OmiColors.textPrimary)

            Spacer()
          }

          Divider()
            .background(OmiColors.backgroundQuaternary)

          // Tier picker — radio-style selector
          VStack(alignment: .leading, spacing: 6) {
            tierPickerRow(tier: 0, label: "Show All Features", subtitle: "Unlock everything")
            tierPickerRow(tier: 1, label: "Tier 1", subtitle: "Conversations + Rewind")
            tierPickerRow(tier: 2, label: "Tier 2", subtitle: "+ Memories (100 memories)")
            tierPickerRow(tier: 3, label: "Tier 3", subtitle: "+ Tasks (100 tasks)")
            tierPickerRow(tier: 4, label: "Tier 4", subtitle: "+ AI Chat (100 conversations)")
            tierPickerRow(
              tier: 5, label: "Tier 5", subtitle: "+ Home (200 convos + 2K screenshots)")
            tierPickerRow(tier: 6, label: "Tier 6", subtitle: "+ Apps (300 conversations)")
          }

          if currentTierLevel > 0 {
            Divider()
              .background(OmiColors.backgroundQuaternary)

            Text("Progress")
              .scaledFont(size: 13, weight: .semibold)
              .foregroundColor(OmiColors.textSecondary)

            // Tier 1 — always unlocked
            tierFeatureRow(
              tier: 1, name: "Conversations + Rewind",
              requirement: "Always unlocked",
              progress: nil, unlocked: true
            )

            // Tier 2 — 100 memories
            tierFeatureRow(
              tier: 2, name: "Memories",
              requirement: "100 memories",
              progress: advancedStats.map { "\($0.memoriesTotal) / 100" },
              unlocked: currentTierLevel >= 2
            )

            // Tier 3 — 100 tasks
            tierFeatureRow(
              tier: 3, name: "Tasks",
              requirement: "100 tasks (todo + done)",
              progress: advancedStats.map { "\($0.tasksTodo + $0.tasksDone) / 100" },
              unlocked: currentTierLevel >= 3
            )

            // Tier 4 — 100 conversations
            tierFeatureRow(
              tier: 4, name: "AI Chat",
              requirement: "100 conversations",
              progress: advancedStats.map { "\($0.conversations) / 100" },
              unlocked: currentTierLevel >= 4
            )

            // Tier 5 — 200 conversations + 2,000 screenshots
            tierFeatureRow(
              tier: 5, name: "Home",
              requirement: "200 conversations + 2K screenshots",
              progress: advancedStats.map {
                "\($0.conversations) / 200 convos, \($0.screenshotsTotal) / 2,000 screenshots"
              },
              unlocked: currentTierLevel >= 5
            )

            // Tier 6 — 300 conversations
            tierFeatureRow(
              tier: 6, name: "Apps",
              requirement: "300 conversations",
              progress: advancedStats.map { "\($0.conversations) / 300" },
              unlocked: currentTierLevel >= 6
            )
          }
        }
      }
    }
  }

  // MARK: - Member Accounts (consumer AI account connect)

  /// "Member Accounts" card: connect a paid consumer account where Omi has a
  /// local bridge. Claude wires to the real Claude Code / ACP bridge and
  /// ChatGPT wires to the real Codex CLI bridge — both have working
  /// Connect/Disconnect actions. Grok has no desktop harness yet and renders
  /// as an honest, disabled "coming soon" row (button is `.disabled(true)`,
  /// so it cannot be tapped — not a silent no-op toggle).
  var aiAccountsCard: some View {
    settingsCard(settingId: "aichat.accounts") {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 10) {
          Image(systemName: "person.crop.circle.badge.checkmark")
            .scaledFont(size: 16)
            .foregroundColor(OmiColors.textTertiary)

          VStack(alignment: .leading, spacing: 3) {
            Text("Member Accounts")
              .scaledFont(size: 15, weight: .semibold)
              .foregroundColor(OmiColors.textPrimary)
            Text("Connect a paid consumer account where Omi has a local bridge.")
              .scaledFont(size: 12)
              .foregroundColor(OmiColors.textTertiary)
          }

          Spacer()
        }

        Divider()

        aiAccountRow(
          provider: .claude,
          isConnected: chatProvider?.isClaudeConnected == true,
          subtitle: "Use your Claude Pro/Max subscription via the local Claude Code bridge.",
          connectTitle: chatProvider?.isClaudeConnected == true ? "Reconnect" : "Connect",
          comingSoon: false,
          connectAction: connectClaudeAccount,
          disconnectAction: {
            Task { await chatProvider?.disconnectClaude() }
          }
        )

        Divider()

        aiAccountRow(
          provider: .chatgpt,
          isConnected: chatProvider?.isChatGPTConnected == true,
          subtitle: "Uses your ChatGPT plan via OpenAI Codex.",
          connectTitle: chatProvider?.isChatGPTConnected == true ? "Reconnect" : "Connect",
          comingSoon: false,
          connectAction: connectChatGPTAccount,
          disconnectAction: {
            Task { await chatProvider?.disconnectChatGPT() }
          }
        )

        Divider()

        aiAccountRow(
          provider: .grok,
          isConnected: false,
          subtitle: "Coming soon — requires a desktop harness for your Grok (xAI) account.",
          connectTitle: "Coming soon",
          comingSoon: true,
          connectAction: {},
          disconnectAction: {}
        )
      }
    }
    .onAppear {
      chatProvider?.checkClaudeConnectionStatus()
      chatProvider?.checkChatGPTConnectionStatus()
    }
  }

  private func aiAccountRow(
    provider: ExternalAIAccountProvider,
    isConnected: Bool,
    subtitle: String,
    connectTitle: String,
    comingSoon: Bool,
    connectAction: @escaping () -> Void,
    disconnectAction: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 12) {
      ConnectorBrandIcon(
        brand: connectorBrand(for: provider),
        size: 24,
        cornerRadius: 6
      )

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(provider.displayName)
            .scaledFont(size: 14, weight: .medium)
            .foregroundColor(OmiColors.textPrimary)

          if isConnected {
            Text("Connected")
              .scaledFont(size: 10, weight: .semibold)
              .foregroundColor(OmiColors.success)
          }
        }

        Text(subtitle)
          .scaledFont(size: 12)
          .foregroundColor(OmiColors.textTertiary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()

      if isConnected {
        Button("Disconnect", action: disconnectAction)
          .buttonStyle(.bordered)
          .controlSize(.small)
      }

      Button(connectTitle, action: connectAction)
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(comingSoon)
    }
  }

  private func connectorBrand(for provider: ExternalAIAccountProvider) -> ConnectorBrand {
    switch provider {
    case .claude: return .claude
    case .chatgpt: return .chatgpt
    case .grok: return .x
    }
  }

  private func connectClaudeAccount() {
    chatBridgeMode = ChatProvider.BridgeMode.userClaude.rawValue
    Task {
      await chatProvider?.switchBridgeMode(to: .userClaude)
      chatProvider?.checkClaudeConnectionStatus()
      chatProvider?.startClaudeAuth()
    }
  }

  private func connectChatGPTAccount() {
    chatBridgeMode = ChatProvider.BridgeMode.userChatGPT.rawValue
    Task {
      await chatProvider?.switchBridgeMode(to: .userChatGPT)
      chatProvider?.checkChatGPTConnectionStatus()
      // If already connected (auth.json present), skip the login browser flow.
      if chatProvider?.isChatGPTConnected != true {
        chatProvider?.startChatGPTAuth()
      }
    }
  }

  // MARK: - OpenRouter key (standalone, independent of BYOK)

  func openRouterKeyCard(settingId: String) -> some View {
    settingsCard(settingId: settingId) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Image(systemName: "network")
            .scaledFont(size: 16)
            .foregroundColor(OmiColors.textTertiary)

          VStack(alignment: .leading, spacing: 3) {
            Text("OpenRouter API Key")
              .scaledFont(size: 14, weight: .medium)
              .foregroundColor(OmiColors.textPrimary)
            Text(
              "Routes local agent and OpenRouter-backed model calls through your key. Separate from the four-provider BYOK free plan."
            )
            .scaledFont(size: 12)
            .foregroundColor(OmiColors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
          }

          Spacer()

          if !devOpenRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Configured")
              .scaledFont(size: 11, weight: .semibold)
              .foregroundColor(OmiColors.success)
          }
        }

        OpenRouterConnectButton(onConnected: { key in
          devOpenRouterKey = key
          applyOpenRouterKeyToEnvironment(key)
        })

        Text("or paste a key manually")
          .scaledFont(size: 11)
          .foregroundColor(OmiColors.textTertiary)

        HStack(spacing: 8) {
          SecureField("sk-or-v1-...", text: $devOpenRouterKey)
            .textFieldStyle(.roundedBorder)
            .scaledFont(size: 13)
            .onChange(of: devOpenRouterKey) { _, newValue in
              applyOpenRouterKeyToEnvironment(newValue)
            }

          if !devOpenRouterKey.isEmpty {
            Button("Clear") {
              devOpenRouterKey = ""
              applyOpenRouterKeyToEnvironment("")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
      }
    }
  }

  func applyOpenRouterKeyToEnvironment(_ value: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      unsetenv("OPENROUTER_API_KEY")
      unsetenv("OMI_OPENROUTER_API_KEY")
    } else {
      setenv("OPENROUTER_API_KEY", trimmed, 1)
      setenv("OMI_OPENROUTER_API_KEY", trimmed, 1)
    }
  }

  // MARK: - Voice Engine: ChatGPT-subscription cascade (Pass 2 — live)

  /// The engine Pass 2 actually wires (`PushToTalkManager.effectiveVoiceEngine`
  /// reads the same persisted key + gate, so this row can never silently drift
  /// from what a PTT turn does). Falls back to native whenever the stored
  /// selection isn't currently runnable — see `VoiceEngineSelection.effectiveEngine`.
  private var effectiveVoiceEngine: VoiceEngineSelection.Engine {
    let stored = VoiceEngineSelection.Engine(rawValue: voiceEngineSelection) ?? .nativeRealtimeBYOK
    return VoiceEngineSelection.effectiveEngine(
      storedSelection: stored, chatGPTConnected: chatProvider?.isChatGPTConnected == true)
  }

  /// Real, selectable row for the "voice on my ChatGPT plan" engine
  /// (DREAM_BACKLOG item 8 / docs-fork/VOICE_CHATGPT_SUBSCRIPTION_DESIGN.md).
  /// Pass 2 shipped `SubscriptionCascadeCoordinator`, so this is no longer the
  /// Pass 1 `.disabled(true)` placeholder audited in item 6 — the button now
  /// actually persists `voiceEngineSelection`, gated by the same
  /// `VoiceEngineSelection.isAvailable` the runtime checks, so it can never be
  /// tappable-but-inert. Reads the real ChatGPT connection gate for the subtitle
  /// and for whether the row can be selected at all.
  @ViewBuilder
  var voiceEngineChatGPTCascadeRow: some View {
    let chatGPTConnected = chatProvider?.isChatGPTConnected == true
    let available = VoiceEngineSelection.isAvailable(
      .chatGPTSubscriptionCascade, chatGPTConnected: chatGPTConnected)
    let isSelected = effectiveVoiceEngine == .chatGPTSubscriptionCascade

    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(VoiceEngineSelection.Engine.chatGPTSubscriptionCascade.displayName)
            .scaledFont(size: 14, weight: .medium)
            .foregroundColor(OmiColors.textPrimary)
          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .scaledFont(size: 12)
              .foregroundColor(OmiColors.purplePrimary)
          }
        }

        Text(VoiceEngineSelection.chatGPTCascadeSubtitle(chatGPTConnected: chatGPTConnected))
          .scaledFont(size: 12)
          .foregroundColor(OmiColors.textTertiary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()

      Button(isSelected ? "Switch back" : (available ? "Use this" : "Connect ChatGPT first")) {
        voiceEngineSelection =
          (isSelected
            ? VoiceEngineSelection.Engine.nativeRealtimeBYOK
            : VoiceEngineSelection.Engine.chatGPTSubscriptionCascade).rawValue
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .disabled(!available && !isSelected)
    }
  }

  // MARK: - Voice Model bring-your-own-key (realtime, multimodal)

  /// Bring-your-own-key field for the Voice Model picker, shown inside that card.
  /// The picker's Auto/Gemini/GPT choice is resolved to the concrete model the hub
  /// will actually connect, and a key field for THAT provider is surfaced:
  ///   • Gemini 3.1 Flash Live → your Google Gemini key (`dev_gemini_api_key`)
  ///   • GPT Realtime 2       → your OpenAI key (`dev_openai_api_key`)
  /// When a key is set, RealtimeHubController.ensureWarm connects client-direct with
  /// it (Omi never sees it). When blank, managed users connect via an Omi-minted
  /// ephemeral token. These are the SAME keys as the free-plan Developer keys.
  @ViewBuilder
  var realtimeVoiceKeyField: some View {
    let effectiveRaw = RealtimeOmniSettings.shared.effectiveProvider.rawValue
    let providerName = VoiceProviderSelection.realtimeProviderDisplayName(forModel: effectiveRaw)
    let usesOpenAI =
      VoiceProviderSelection.realtimeKeyStorageKey(forModel: effectiveRaw)
      == BYOKProvider.openai.storageKey
    let keyBinding = usesOpenAI ? $devOpenAIKey : $devGeminiKey
    let hasKey = VoiceProviderSelection.realtimeUsesOwnKey(
      hasProviderKey: !keyBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )

    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Your \(providerName) key")
          .scaledFont(size: 13, weight: .medium)
          .foregroundColor(OmiColors.textPrimary)
        Spacer()
        Text(hasKey ? "Using your key" : "Omi-managed")
          .scaledFont(size: 11, weight: .semibold)
          .foregroundColor(hasKey ? OmiColors.success : OmiColors.textTertiary)
      }

      Text(
        hasKey
          ? "Live voice connects directly to \(providerName) with your key — Omi never sees it."
          : "Leave blank to use Omi's managed voice. Add your own \(providerName) key to run live voice on your own account (same key as the free-plan Developer keys)."
      )
      .scaledFont(size: 12)
      .foregroundColor(OmiColors.textTertiary)
      .fixedSize(horizontal: false, vertical: true)

      if usesOpenAI && !hasKey {
        // Honest label per the ChatGPT-subscription voice design doc: this key is a
        // separate, billed OpenAI Platform key (sk-) — a ChatGPT Plus/Pro/Codex
        // subscription cannot authorize GPT Realtime, so it will never work here.
        Text("This is a funded OpenAI Platform key (sk-), billed by OpenAI — your ChatGPT subscription does not work here.")
          .scaledFont(size: 11)
          .foregroundColor(OmiColors.textTertiary)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack(spacing: 8) {
        SecureField(usesOpenAI ? "sk-..." : "AIza...", text: keyBinding)
          .textFieldStyle(.roundedBorder)
          .scaledFont(size: 13)
          .onChange(of: keyBinding.wrappedValue) { _, _ in
            // Re-warm the hub so the new key (or its removal) takes effect, and keep the
            // four-key BYOK free-plan gate consistent — these are the same keys.
            NotificationCenter.default.post(name: .realtimeOmniSettingsDidChange, object: nil)
            refreshBYOKActivation()
          }

        if hasKey {
          Button("Clear") { keyBinding.wrappedValue = "" }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
      }
    }
  }

  // MARK: - Transcription (STT) provider + key

  /// Two-way binding between the persisted STT state (`forceCloudSTT` +
  /// `dev_deepgram_api_key`) and the three-way Transcription picker.
  var transcriptionChoiceBinding: Binding<VoiceProviderSelection.TranscriptionChoice> {
    Binding(
      get: {
        VoiceProviderSelection.transcriptionChoice(
          forceCloud: forceCloudSTT,
          hasDeepgramKey: !devDeepgramKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      },
      set: { newChoice in
        let state = VoiceProviderSelection.transcriptionState(for: newChoice)
        forceCloudSTT = state.forceCloud
        if state.clearDeepgramKey { devDeepgramKey = "" }
        refreshBYOKActivation()
      }
    )
  }

  var transcriptionSubtitle: String {
    switch VoiceProviderSelection.transcriptionChoice(
      forceCloud: forceCloudSTT,
      hasDeepgramKey: !devDeepgramKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    ) {
    case .onDevice:
      return
        "Speech-to-text runs on your Mac (Apple Silicon). No audio leaves your device. Applies to new recordings."
    case .omiCloud:
      return "Uses Omi's managed Deepgram cloud transcription. Applies to new recordings."
    case .deepgramBYO:
      return "Cloud transcription billed to your own Deepgram key. Applies to new recordings."
    }
  }

  /// Transcription (STT) card — a control DISTINCT from the Voice Model picker.
  /// Deepgram is audio→text only (no vision), so it never appears in the Voice Model
  /// slot; it lives here with on-device and Omi-cloud alternatives.
  var voiceTranscriptionCard: some View {
    settingsCard(settingId: "aichat.transcription") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Image(systemName: "waveform.badge.mic")
            .scaledFont(size: 16)
            .foregroundColor(OmiColors.textTertiary)

          Text("Transcription")
            .scaledFont(size: 15, weight: .semibold)
            .foregroundColor(OmiColors.textPrimary)

          Spacer()

          Picker("", selection: transcriptionChoiceBinding) {
            Text("On-device (private)").tag(VoiceProviderSelection.TranscriptionChoice.onDevice)
            Text("Omi cloud").tag(VoiceProviderSelection.TranscriptionChoice.omiCloud)
            Text("Deepgram (your key)").tag(VoiceProviderSelection.TranscriptionChoice.deepgramBYO)
          }
          .pickerStyle(.menu)
          .frame(width: 200)
        }

        Text(transcriptionSubtitle)
          .scaledFont(size: 12)
          .foregroundColor(OmiColors.textTertiary)
          .fixedSize(horizontal: false, vertical: true)

        if VoiceProviderSelection.transcriptionChoice(
          forceCloud: forceCloudSTT,
          hasDeepgramKey: !devDeepgramKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ) == .deepgramBYO {
          HStack(spacing: 8) {
            SecureField("Deepgram API key", text: $devDeepgramKey)
              .textFieldStyle(.roundedBorder)
              .scaledFont(size: 13)
              .onChange(of: devDeepgramKey) { _, _ in refreshBYOKActivation() }

            if !devDeepgramKey.isEmpty {
              Button("Clear") { devDeepgramKey = "" }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
          }
        }
      }
    }
  }

}
