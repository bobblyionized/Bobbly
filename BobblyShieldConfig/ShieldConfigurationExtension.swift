//  ShieldConfigurationExtension.swift
//  BobblyShieldConfig — principal class (see Info.plist). Decides the
//  content, delegates the look to `ShieldStyle`.

import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let shared = SharedStore.shared

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        ShieldStyle.configuration(for: content(for: application))
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        ShieldStyle.configuration(for: content(for: application))
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        ShieldStyle.configuration(for: ShieldContentBuilder.make(appName: webDomain.domain, isStudy: isStudyOnly(webDomain: webDomain), isWebsite: true, shared: shared))
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        ShieldStyle.configuration(for: ShieldContentBuilder.make(appName: webDomain.domain, isStudy: isStudyOnly(webDomain: webDomain), isWebsite: true, shared: shared))
    }

    // MARK: - Helpers

    private func content(for application: Application) -> ShieldContent {
        let name = application.localizedDisplayName
        if let token = application.token, let name, let data = TokenCoding.encode(token) {
            shared.lastShieldedApp = ShieldedAppName(applicationTokenData: data, name: name, recordedAt: Date())
        }
        return ShieldContentBuilder.make(appName: name, isStudy: isStudyOnly(application: application), isWebsite: false, shared: shared)
    }

    /// `true` when the app is shielded only because of a study session
    /// (not on the regular block list).
    private func isStudyOnly(application: Application) -> Bool {
        guard shared.activeStudy?.isActive(at: Date()) == true else { return false }
        guard let token = application.token else { return true }
        return !shared.blockedSelection.applicationTokens.contains(token)
    }

    private func isStudyOnly(webDomain: WebDomain) -> Bool {
        guard shared.activeStudy?.isActive(at: Date()) == true else { return false }
        guard let token = webDomain.token else { return true }
        return !shared.blockedSelection.webDomainTokens.contains(token)
    }
}
