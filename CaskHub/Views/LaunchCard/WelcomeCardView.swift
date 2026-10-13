//
//  WelcomeCardView.swift
//  CaskHub
//
//  Created by Ali Elsokary on 04/10/2026.
//

import SwiftUI

enum WelcomePage: Int, CaseIterable {
    case intro, categories, recentlyAdded, manage, adopt, look, privacy, ready

    struct Spec {
        let symbol: String?
        let tint: Color
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
    }

    var spec: Spec {
        switch self {
        case .intro:
            Spec(symbol: nil, tint: .chTerracotta, title: .launchCardWelcomeIntroTitle, detail: .launchCardWelcomeIntroDetail)
        case .categories:
            Spec(symbol: DiscoverItem.browse.icon, tint: .chSage,
                 title: .launchCardWelcomeCategoriesTitle, detail: .launchCardWelcomeCategoriesDetail)
        case .recentlyAdded:
            Spec(symbol: DiscoverItem.recentlyAdded.icon, tint: .chPlum,
                 title: .launchCardWelcomeRecentlyAddedTitle, detail: .launchCardWelcomeRecentlyAddedDetail)
        case .manage:
            Spec(symbol: LibraryItem.updates.icon, tint: .chTerracotta,
                 title: .launchCardWelcomeManageTitle, detail: .launchCardWelcomeManageDetail)
        case .adopt:
            Spec(symbol: LibraryItem.adopt.icon, tint: .chSage,
                 title: .launchCardWelcomeAdoptTitle, detail: .launchCardWelcomeAdoptDetail)
        case .look:
            Spec(symbol: "paintbrush", tint: .chPlum, title: .launchCardWelcomeLookTitle, detail: .launchCardWelcomeLookDetail)
        case .privacy:
            Spec(symbol: "hand.raised", tint: .chAmber,
                 title: .launchCardWelcomePrivacyTitle, detail: .launchCardWelcomePrivacyDetail)
        case .ready:
            Spec(symbol: "checkmark.seal.fill", tint: .chSage,
                 title: .launchCardWelcomeReadyTitle, detail: .launchCardWelcomeReadyDetail)
        }
    }
}

struct WelcomeLookConfirmation {
    private var confirmedStyle: AppStyle?

    mutating func confirm(_ style: AppStyle) {
        guard style != confirmedStyle else { return }
        confirmedStyle = style
        Analytics.welcomeLookConfirmed(style)
    }
}

struct WelcomeCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: WelcomePage
    @State private var lookConfirmation = WelcomeLookConfirmation()

    init(page: WelcomePage = .intro) {
        _page = State(initialValue: page)
    }

    private var isLastPage: Bool {
        page == WelcomePage.allCases.last
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(WelcomePage.allCases, id: \.self) { item in
                    WelcomePageView(page: item, isActive: item == page)
                        .opacity(item == page ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: page)
                        .allowsHitTesting(item == page)
                        .disabled(item != page)
                        .accessibilityHidden(item != page)
                }
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .frame(width: 600, height: 480)
        .onDisappear { Analytics.launchCardDismissed(.welcome, page: page.rawValue + 1, style: AppStyle.current) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if !isLastPage {
                Button(String(localized: .launchCardButtonSkip)) {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(CHType.button)
                .foregroundStyle(Color.chTextMuted)
            }
            Spacer()
            if page != .intro {
                LaunchCardButton(title: .launchCardButtonBack, isProminent: false) {
                    move(by: -1)
                }
            }
            LaunchCardButton(
                title: isLastPage ? .launchCardButtonGetStarted : .launchCardButtonNext,
                isProminent: true
            ) {
                if isLastPage {
                    dismiss()
                } else {
                    if page == .look { lookConfirmation.confirm(AppStyle.current) }
                    move(by: 1)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .overlay { pageDots }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Color.chHairline.frame(height: 1) }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(WelcomePage.allCases, id: \.self) { item in
                Button {
                    page = item
                } label: {
                    Capsule()
                        .fill(item == page ? Color.chAccent : Color.chTextFaint.opacity(0.5))
                        .frame(width: item == page ? 20 : 6, height: 6)
                        .frame(height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.3), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.launchCardWelcomePageIndicator(page.rawValue + 1, WelcomePage.allCases.count)))
    }

    private func move(by offset: Int) {
        guard let next = WelcomePage(rawValue: page.rawValue + offset) else { return }
        page = next
    }
}

private struct WelcomePageView: View {
    let page: WelcomePage
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.frame(maxHeight: .infinity)
            ScrollView { content }
        }
    }

    private var content: some View {
        VStack(spacing: 14) {
            hero
            Text(page.spec.title)
                .font(CHType.Catalog(scale: 0.8).hero)
                .foregroundStyle(Color.chTextTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 30)
            Text(page.spec.detail)
                .font(CHType.body)
                .foregroundStyle(Color.chTextBody)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 36, alignment: .top)
            accessory
                .padding(.top, 6)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var isHeldBack: Bool {
        page == .ready && !isActive && !reduceMotion
    }

    private func entrance(delay: Double) -> Animation? {
        if reduceMotion { return nil }
        return isActive ? .spring(duration: 0.6, bounce: 0.3).delay(delay) : .easeOut(duration: 0.2)
    }

    @ViewBuilder private var hero: some View {
        if let symbol = page.spec.symbol {
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(page.spec.tint)
                .frame(height: 64)
                .scaleEffect(isHeldBack ? 0.3 : 1)
                .rotationEffect(.degrees(isHeldBack ? -30 : 0))
                .animation(entrance(delay: 0.06), value: isActive)
                .accessibilityHidden(true)
        } else {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var accessory: some View {
        switch page {
        case .look:
            VStack(spacing: 10) {
                AppStylePicker(scale: 0.68)
                MatchSystemToggle(showsDetail: false)
                    .font(CHType.body)
                    .foregroundStyle(Color.chTextTitle)
                    .tint(Color.chAccent)
            }
        case .privacy:
            WelcomePrivacyToggles()
        case .ready:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(WelcomeShortcutRow.all.enumerated()), id: \.offset) { index, row in
                    row
                        .opacity(isActive ? 1 : 0)
                        .offset(x: isHeldBack ? -10 : 0)
                        .animation(entrance(delay: 0.3 + Double(index) * 0.11), value: isActive)
                }
            }
        default:
            EmptyView()
        }
    }
}

private struct WelcomePrivacyToggles: View {
    @AppStorage(Analytics.enabledKey) private var analyticsEnabled = true
    @AppStorage(CrashReporter.enabledKey) private var crashReportingEnabled = true

    var body: some View {
        VStack(spacing: 10) {
            toggle("Share anonymous usage analytics", isOn: $analyticsEnabled)
            Color.chHairline.frame(height: 1)
            toggle("Share crash reports", isOn: $crashReportingEnabled)
        }
        .toggleStyle(.switch)
        .tint(Color.chAccent)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: CHRadius.card).fill(Color.chSurfaceField))
        .overlay(RoundedRectangle(cornerRadius: CHRadius.card).strokeBorder(Color.chHairline, lineWidth: 1))
        .frame(maxWidth: 380)
        .applyingPrivacyChanges(analytics: analyticsEnabled, crashReports: crashReportingEnabled)
    }

    private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(CHType.body)
                .foregroundStyle(Color.chTextTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WelcomeShortcutRow: View {
    let keys: [String]
    let label: LocalizedStringResource

    static let all = [
        WelcomeShortcutRow(keys: ["⌘F"], label: .launchCardWelcomeShortcutSearch),
        WelcomeShortcutRow(keys: ["⌘1", "⌘2"], label: .launchCardWelcomeShortcutViewMode),
        WelcomeShortcutRow(keys: ["⌘,"], label: .launchCardWelcomeShortcutSettings)
    ]

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { Keycap(symbol: $0) }
            }
            .frame(width: 64, alignment: .trailing)
            Text(label)
                .font(CHType.body)
                .foregroundStyle(Color.chTextBody)
        }
        .accessibilityElement(children: .combine)
    }
}
