//  StudyView.swift
//  Bobbly/Features/Study — pick a whitelist and a length, then study with
//  everything else blocked. A running session shows a ring timer; ending
//  early goes through Bobbly. Contract: StudyViewModel.

import SwiftUI

struct StudyView: View {
    @Bindable var model: StudyViewModel
    @Environment(AppEnvironment.self) private var env

    init(model: StudyViewModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let session = model.activeSession {
                        SessionPanel(session: session) { model.requestEndEarly() }
                        if let error = model.errorMessage {
                            InlineNotice(kind: .error, text: error)
                        }
                    } else {
                        setup
                    }

                    Label(model.alwaysAllowedNote, systemImage: "phone.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
                .animation(Theme.Motion.reveal, value: model.isSessionRunning)
            }
            .bobblyPage()
            .navigationTitle("Study")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        env.router.present(.whitelistEditor(whitelistID: nil))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New whitelist")
                }
            }
        }
        .onAppear { model.onAppear() }
        .bobblyHaptic(.start, trigger: model.isSessionRunning)
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Block everything except the apps on a whitelist, until the timer ends.")
                .font(.callout)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionTitle("Whitelist") {
                    if !model.whitelists.isEmpty {
                        Button("New") { env.router.present(.whitelistEditor(whitelistID: nil)) }
                            .font(.subheadline.weight(.semibold))
                            .tint(Theme.Palette.pond)
                    }
                }
                if model.whitelists.isEmpty {
                    Panel {
                        EmptyStateView(title: "No whitelists yet",
                                       message: "A whitelist is the handful of apps you can still use while studying, like Notes, Calculator or Khan Academy.",
                                       mood: .happy) {
                            Button("Create a whitelist") {
                                env.router.present(.whitelistEditor(whitelistID: nil))
                            }
                            .buttonStyle(.bobbly(.primary, fullWidth: false))
                        }
                    }
                } else {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(model.whitelists) { list in
                            WhitelistRow(summary: list,
                                         detail: detail(for: list),
                                         isSelected: model.selectedWhitelistID == list.id,
                                         onSelect: { model.selectedWhitelistID = list.id },
                                         onEdit: { openEditor(for: list.id) },
                                         onDelete: { model.delete(list.id) })
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionTitle("Length")
                FlowLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
                    ForEach(model.durationOptions) { option in
                        ChoiceChip(title: option.title, isSelected: option == model.selectedDuration) {
                            model.selectedDuration = option
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if let error = model.errorMessage {
                    InlineNotice(kind: .error, text: error)
                        .transition(.opacity)
                }
                Button {
                    model.startSession()
                } label: {
                    Label("Start studying", systemImage: "play.fill")
                }
                .buttonStyle(.bobblyPrimary)
                .disabled(!model.canStart)
            }
            .animation(Theme.Motion.standard, value: model.errorMessage)
        }
        .bobblyHaptic(trigger: model.errorMessage) { _, new in
            new == nil ? nil : SensoryFeedback.error
        }
    }

    /// Loads the whitelist into the draft, then shows the editor sheet.
    private func openEditor(for id: UUID) {
        model.edit(id)
        env.router.present(.whitelistEditor(whitelistID: id))
    }

    private func detail(for list: WhitelistSummary) -> String {
        if model.engineKind == .familyControls {
            var parts: [String] = []
            if list.appCount > 0 { parts.append(Fmt.count(list.appCount, "app")) }
            if list.categoryCount > 0 { parts.append(Fmt.count(list.categoryCount, "category", "categories")) }
            if list.webDomainCount > 0 { parts.append(Fmt.count(list.webDomainCount, "website")) }
            return parts.isEmpty ? "No apps picked yet" : parts.joined(separator: ", ")
        }
        return list.allowedAppNames.isEmpty ? "No apps picked yet" : list.allowedAppNames.joined(separator: ", ")
    }
}

// MARK: - Running session

private struct SessionPanel: View {
    let session: ActiveStudySession
    let onEndEarly: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = session.remaining(at: context.date)
                let elapsed = session.elapsed(at: context.date)
                let progress = session.progress(at: context.date)
                    ?? elapsed.truncatingRemainder(dividingBy: 3600) / 3600
                ZStack {
                    RingProgress(progress: progress, lineWidth: 14, tint: Theme.Palette.reed)
                        .animation(.linear(duration: 1), value: progress)
                    VStack(spacing: 2) {
                        Text(Fmt.clock(remaining ?? elapsed))
                            .scaledFont(size: 46, relativeTo: .largeTitle, weight: .semibold, monospacedDigits: true)
                            .foregroundStyle(Theme.Palette.ink)
                            .contentTransition(.numericText(countsDown: remaining != nil))
                        Text(remaining != nil ? "left" : "so far")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }
                .frame(width: 236, height: 236)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(remaining.map { "\(Fmt.duration($0)) left" } ?? "\(Fmt.duration(elapsed)) so far")
            }

            VStack(spacing: Theme.Spacing.xxs) {
                Text("Studying with \(session.whitelistName)")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(session.endsAt.map { "Ends at \(Fmt.time($0)). Only \(session.whitelistName) apps can open." }
                     ?? "Runs until you stop it. Only \(session.whitelistName) apps can open.")
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Button("End early", action: onEndEarly)
                    .buttonStyle(.bobblySecondary)
                Text("Bobbly will ask why first.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
    }
}

// MARK: - Whitelist row

private struct WhitelistRow: View {
    let summary: WhitelistSummary
    let detail: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button(action: onSelect) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.Palette.reed : Theme.Palette.inkTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Text(summary.needsRepick ? "Screen Time was reset, so its apps need picking again." : detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if summary.needsRepick {
                Button(action: onEdit) {
                    Label("Pick apps again", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.amber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.Palette.amber.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pick apps again for \(summary.name)")
            }

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.pond)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.pond.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(summary.name)")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .stroke(isSelected ? Theme.Palette.reed : Color.clear, lineWidth: 2)
        }
        .animation(Theme.Motion.standard, value: isSelected)
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

#Preview {
    let env = AppEnvironment.preview()
    StudyView(model: env.study)
        .environment(env)
}
