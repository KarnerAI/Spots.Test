//
//  SettingsView.swift
//  Spots.Test
//
//  Created for Spots 2.0 Settings (Figma node 66-58).
//

import SwiftUI

// MARK: - Design Tokens (Figma)

private enum SettingsColors {
    static let primaryText = Color(red: 0.063, green: 0.094, blue: 0.157)   // #101828
    static let secondaryText = Color(red: 0.42, green: 0.45, blue: 0.51)     // #6a7282
    static let border = Color.gray200                                       // #e5e7eb
    static let rowDivider = Color.gray100                                   // #f3f4f6
    static let iconBgTeal = Color.spotsTeal.opacity(0.1)
    static let iconBgGray = Color.gray100
    static let deleteTitle = Color(red: 0.91, green: 0, blue: 0.04)          // #e7000b
    static let deleteIconBg = Color(red: 0.996, green: 0.949, blue: 0.949)   // #fef2f2
    static let footerText = Color(red: 0.6, green: 0.63, blue: 0.69)         // #99a1af
}

private struct SettingsRowConfig {
    let iconName: String
    let iconBg: Color
    let title: String
    let subtitle: String
    let showChevron: Bool
    let titleColor: Color
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel

    private let rowHeight: CGFloat = 72.67
    private let horizontalPadding: CGFloat = 24
    private let sectionHeaderTopPadding: CGFloat = 24
    private let iconSize: CGFloat = 40
    private let symbolSize: CGFloat = 20
    private let iconTextGap: CGFloat = 12

    private var accountRows: [SettingsRowConfig] {
        [
            SettingsRowConfig(iconName: "person.crop.circle", iconBg: SettingsColors.iconBgTeal, title: "Edit Profile", subtitle: "Update your profile information", showChevron: true, titleColor: SettingsColors.primaryText),
            SettingsRowConfig(iconName: "person.2", iconBg: SettingsColors.iconBgTeal, title: "Invite Friends", subtitle: "Share Spots with your friends", showChevron: true, titleColor: SettingsColors.primaryText),
        ]
    }

    private var preferencesRows: [SettingsRowConfig] {
        [
            SettingsRowConfig(iconName: "bell", iconBg: SettingsColors.iconBgGray, title: "Notifications", subtitle: "Manage notification settings", showChevron: true, titleColor: SettingsColors.primaryText),
            SettingsRowConfig(iconName: "lock", iconBg: SettingsColors.iconBgGray, title: "Privacy", subtitle: "Control your privacy settings", showChevron: true, titleColor: SettingsColors.primaryText),
        ]
    }

    private var supportRows: [SettingsRowConfig] {
        [
            SettingsRowConfig(iconName: "questionmark.circle", iconBg: SettingsColors.iconBgGray, title: "Help & Support", subtitle: "Get help with Spots", showChevron: true, titleColor: SettingsColors.primaryText),
            SettingsRowConfig(iconName: "doc.text", iconBg: SettingsColors.iconBgGray, title: "Terms & Privacy Policy", subtitle: "Read our legal documents", showChevron: true, titleColor: SettingsColors.primaryText),
        ]
    }

    private var accountActionsRows: [SettingsRowConfig] {
        [
            SettingsRowConfig(iconName: "rectangle.portrait.and.arrow.right", iconBg: SettingsColors.iconBgGray, title: "Log Out", subtitle: "Sign out of your account", showChevron: false, titleColor: SettingsColors.primaryText),
            SettingsRowConfig(iconName: "trash", iconBg: SettingsColors.deleteIconBg, title: "Delete Account", subtitle: "Permanently delete your account", showChevron: false, titleColor: SettingsColors.deleteTitle),
        ]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("ACCOUNT")
                accountSection

                sectionHeader("PREFERENCES")
                    .padding(.top, sectionHeaderTopPadding)
                settingsSection(rows: preferencesRows) { config in
                    rowTapped(config)
                }

                sectionHeader("SUPPORT")
                    .padding(.top, sectionHeaderTopPadding)
                settingsSection(rows: supportRows) { config in
                    rowTapped(config)
                }

                sectionHeader("ACCOUNT ACTIONS")
                    .padding(.top, sectionHeaderTopPadding)
                accountActionsSection

                footer
                    .padding(.top, 32)
                    .padding(.bottom, 100)
            }
        }
        .background(Color.white)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.white, for: .navigationBar)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.3)
            .foregroundColor(SettingsColors.secondaryText)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 8)
    }

    /// ACCOUNT section: "Edit Profile" navigates to EditProfileView; other rows use a button.
    private var accountSection: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: EditProfileView()) {
                settingsRow(accountRows[0])
            }
            .buttonStyle(.plain)

            Divider()
                .background(SettingsColors.rowDivider)
                .padding(.leading, horizontalPadding + iconSize + iconTextGap)

            Button {
                rowTapped(accountRows[1])
            } label: {
                settingsRow(accountRows[1])
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
    }

    private func settingsSection(rows: [SettingsRowConfig], action: @escaping (SettingsRowConfig) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, config in
                Button {
                    action(config)
                } label: {
                    settingsRow(config)
                }
                .buttonStyle(.plain)

                if index < rows.count - 1 {
                    Divider()
                        .background(SettingsColors.rowDivider)
                        .padding(.leading, horizontalPadding + iconSize + iconTextGap)
                }
            }
        }
        .background(Color.white)
    }

    private var accountActionsSection: some View {
        VStack(spacing: 0) {
            Button {
                viewModel.signOut()
            } label: {
                settingsRow(accountActionsRows[0])
            }
            .buttonStyle(.plain)

            Divider()
                .background(SettingsColors.rowDivider)
                .padding(.leading, horizontalPadding + iconSize + iconTextGap)

            Button {
                // Placeholder: delete account not implemented
            } label: {
                settingsRow(accountActionsRows[1])
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
    }

    private func settingsRow(_ config: SettingsRowConfig) -> some View {
        HStack(alignment: .center, spacing: iconTextGap) {
            ZStack {
                Circle()
                    .fill(config.iconBg)
                    .frame(width: iconSize, height: iconSize)

                Image(systemName: config.iconName)
                    .font(.system(size: symbolSize))
                    .foregroundColor(config.iconBg == SettingsColors.deleteIconBg ? SettingsColors.deleteTitle : .spotsTeal)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(config.title)
                    .font(.system(size: 14))
                    .foregroundColor(config.titleColor)

                Text(config.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(SettingsColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if config.showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SettingsColors.secondaryText)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: rowHeight)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Spots v1.0.0")
                .font(.system(size: 12))
                .foregroundColor(SettingsColors.footerText)

            Text("Made with ❤️ for explorers")
                .font(.system(size: 12))
                .foregroundColor(SettingsColors.footerText)
        }
        .frame(maxWidth: .infinity)
    }

    private func rowTapped(_ config: SettingsRowConfig) {
        switch config.title {
        case "Log Out":
            viewModel.signOut()
        default:
            break
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView().environmentObject(AuthenticationViewModel())
    }
}
