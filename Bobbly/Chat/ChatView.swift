//  ChatView.swift
//  Bobbly/Chat — the conversation that decides unlocks. Bubbles, quick-reply
//  chips, typing indicator, cooldown ring, commitment sentence and result
//  cards. Contract: ChatViewModel.

import SwiftUI
import FamilyControls

struct ChatView: View {
    @Bindable var model: ChatViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @FocusState private var isInputFocused: Bool

    init(model: ChatViewModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    transcript
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.top, Theme.Spacing.s)
                        .padding(.bottom, Theme.Spacing.m)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollToBottom(proxy, animated: false) }
                .onChange(of: model.messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: model.isBobblyTyping) { _, _ in scrollToBottom(proxy) }
                .onChange(of: model.quickReplies) { _, _ in scrollToBottom(proxy) }
                .onChange(of: model.outcome) { _, _ in scrollToBottom(proxy) }
                .onChange(of: model.needsAppSelection) { _, _ in scrollToBottom(proxy) }
            }
            .bobblyPage()
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { header }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Start over")
                }
            }
            .toolbarBackground(Theme.Palette.page, for: .navigationBar)
        }
        // Closing the picker finishes the pending unlock: confirmed if apps were
        // picked, cancelled otherwise (ChatViewModel.needsAppSelection).
        .familyActivityPicker(isPresented: $model.needsAppSelection, selection: $model.appSelection)
        .onAppear { model.onAppear() }
        .bobblyHaptic(trigger: model.outcome) { _, new in
            switch new {
            case .some(.failed): return .error
            case .some(.granted), .some(.declined), .some(.studyEnded): return .success
            case .some(.emergency): return .warning
            case .none: return nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            BobblyCharacter(mood: model.companion.tier, moodValue: model.companion.mood, size: 32, isAnimated: false)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Bobbly")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.Palette.ink)
                subtitle
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var subtitle: some View {
        if let target = model.target {
            switch target.subject {
            case .studySession:
                Text("About ending \(target.displayName)")
            case .application, .appName:
                HStack(spacing: 3) {
                    Text("About")
                    AppSubjectLabel(subject: target.subject, fallbackName: target.displayName)
                        .labelStyle(.titleOnly)
                }
            }
        } else {
            Text("Feeling \(model.companion.tier.moodTitle.lowercased())")
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                ChatBubbleView(message: message,
                               showsAvatar: showsAvatar(at: index),
                               avatarMood: model.companion.tier)
                    .padding(.top, startsNewRun(at: index) ? Theme.Spacing.xs : 0)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity))
            }

            if model.isBobblyTyping {
                TypingIndicator(mood: model.companion.tier)
                    .transition(.opacity)
            }

            if let cooldown = model.cooldown {
                CooldownCard(cooldown: cooldown)
                    .padding(.leading, 38)
                    .transition(.opacity)
            }

            if !model.quickReplies.isEmpty {
                FlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
                    ForEach(model.quickReplies) { reply in
                        QuickReplyChip(reply: reply) { model.select(reply) }
                    }
                }
                .padding(.leading, 38)
                .padding(.top, Theme.Spacing.xxs)
                .transition(.opacity)
            }

            if model.needsAppSelection {
                Label("Pick only the app you need. Closing the list unlocks it.", systemImage: "apps.iphone")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .padding(.leading, 38)
                    .transition(.opacity)
            }

            if let outcome = model.outcome {
                OutcomeCard(outcome: outcome,
                            onOpenApp: { url in openURL(url) },
                            onStartOver: { model.reset() },
                            onOpenEmergency: { model.openEmergency() },
                            onBackToStudy: { env.router.showTab(.study) })
                    .padding(.top, Theme.Spacing.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Color.clear
                .frame(height: 1)
                .id(Self.bottomID)
        }
        .animation(Theme.Motion.standard, value: model.messages.count)
        .animation(Theme.Motion.standard, value: model.isBobblyTyping)
        .animation(Theme.Motion.standard, value: model.quickReplies)
        .animation(Theme.Motion.reveal, value: model.outcome)
    }

    private static let bottomID = "chat-bottom"

    /// Avatar on the last bubble of each run of Bobbly messages.
    private func showsAvatar(at index: Int) -> Bool {
        let messages = model.messages
        guard messages[index].sender == .bobbly else { return false }
        if index == messages.count - 1 { return !model.isBobblyTyping }
        return messages[index + 1].sender != .bobbly
    }

    private func startsNewRun(at index: Int) -> Bool {
        index > 0 && model.messages[index - 1].sender != model.messages[index].sender
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(Theme.Motion.standard) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }

    // MARK: Input

    @ViewBuilder private var inputBar: some View {
        if model.acceptsFreeText {
            HStack(alignment: .center, spacing: 10) {
                TextField(model.inputPlaceholder, text: $model.draft)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .autocorrectionDisabled(model.commitmentPhrase != nil)
                    .onSubmit { model.send() }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Theme.Palette.surface, in: Capsule())
                    .overlay { Capsule().stroke(Theme.Palette.hairline, lineWidth: 1) }

                Button {
                    model.send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(model.canSend ? Theme.Palette.onPond : Theme.Palette.inkTertiary)
                        .frame(width: 42, height: 42)
                        .background(model.canSend ? Theme.Palette.pond : Theme.Palette.sunken, in: Circle())
                }
                .disabled(!model.canSend)
                .accessibilityLabel("Send")
                .animation(Theme.Motion.press, value: model.canSend)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .background(.bar)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Cooldown

/// A ring that fills while Bobbly makes you wait. The model ends it itself.
private struct CooldownCard: View {
    let cooldown: ChatCooldown

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = cooldown.remainingSeconds(at: context.date)
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    RingProgress(progress: cooldown.progress(at: context.date), lineWidth: 6, tint: Theme.Palette.amber)
                    Text("\(remaining)")
                        .font(Theme.Typography.numeralSmall)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.ink)
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 64, height: 64)
                .animation(.linear(duration: 1), value: remaining)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cooling off")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.ink)
                    Text("When the ring fills, you can unlock anyway. Still want it then?")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cooling off. \(remaining) seconds left before you can unlock anyway.")
        }
    }
}

// MARK: - Outcome

private struct OutcomeCard: View {
    let outcome: ChatOutcome
    let onOpenApp: (URL) -> Void
    let onStartOver: () -> Void
    let onOpenEmergency: () -> Void
    let onBackToStudy: () -> Void

    var body: some View {
        switch outcome {
        case .granted(let appName, let minutes, let until, let costLife, let reopenURL):
            card(symbol: "lock.open.fill", tint: Theme.Palette.amber,
                 title: "\(appName) is unlocked",
                 message: "For \(Fmt.option(minutes: minutes)), until \(Fmt.time(until)). Bobbly locks it again after that.") {
                HStack(spacing: Theme.Spacing.xs) {
                    CountdownText(until: until)
                    Text("left")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                if costLife {
                    InlineNotice(kind: .warning, text: "This unlock cost Bobbly a life.")
                }
                if let reopenURL {
                    Button("Open \(appName)") { onOpenApp(reopenURL) }
                        .buttonStyle(.bobblyPrimary)
                }
                Button("Start over") { onStartOver() }
                    .buttonStyle(.bobblyQuiet)
            }

        case .studyEnded(let name):
            card(symbol: "book.closed.fill", tint: Theme.Palette.reed,
                 title: "\(name) session ended",
                 message: "Your apps are back to your usual blocking.") {
                Button("Back to Study") { onBackToStudy() }
                    .buttonStyle(.bobblySecondary)
                Button("Start over") { onStartOver() }
                    .buttonStyle(.bobblyQuiet)
            }

        case .declined:
            VStack(spacing: Theme.Spacing.s) {
                BobblyCharacter(mood: .thriving, moodValue: 95, size: 96)
                Text("You said no. Bobbly's proud of you.")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center)
                Text("Every no gives Bobbly a little boost.")
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                Button("Start over") { onStartOver() }
                    .buttonStyle(.bobbly(.secondary, fullWidth: false))
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.l)
            .background(Theme.Palette.reed.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))

        case .emergency:
            card(symbol: "exclamationmark.octagon.fill", tint: Theme.Palette.signal,
                 title: "Emergency screen",
                 message: "Hold the button there for 10 seconds. Emergency unblocks are always free.") {
                Button("Open Emergency") { onOpenEmergency() }
                    .buttonStyle(.bobblyDanger)
            }

        case .failed(let message):
            card(symbol: "exclamationmark.triangle.fill", tint: Theme.Palette.signal,
                 title: "That didn't work",
                 message: message) {
                Button("Start over") { onStartOver() }
                    .buttonStyle(.bobblySecondary)
            }
        }
    }

    private func card<Actions: View>(symbol: String, tint: Color, title: String, message: String,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
    }
}

#Preview {
    let env = AppEnvironment.preview()
    ChatView(model: env.chat)
        .environment(env)
}
