# Origin and personal fork

This repository is a personal derivative maintained under the JY-Luuu account.

- Original project: https://github.com/yuxuanfuture/hang-later
- Original author: Yuxuan Fu
- Base release: v0.10.0
- Base commit: dc1b93abc9a6ab6ff845cfa33df309e43694a9cd
- Original license: MIT; retained in LICENSE.
- Third-party source: Alejandro Buján / Tendedero, as documented in THIRD_PARTY_NOTICES.md.

The paper artwork, interface design and original application implementation come from the upstream project. The personal fork does not claim original authorship of those parts.

## Personal changes

The first personal version intentionally preserves the original screens and behavior. It introduces a personal app display name, bundle identifier, data directory, browser host and extension identity; updates repository and distribution instructions; adds identity and browser-process integration checks; supports explicit SwiftPM sandbox opt-out in restricted build hosts; supplies an ICNS fallback using the same generated PNG artwork; and adds macOS 15 CI and personal release artifact names.

Internal Swift target names remain compatible with the upstream implementation. The main wordmark, receipt and icon use QIZHI, and the system-visible application name is 栖纸 Qizhi. Personal data is isolated rather than automatically importing or changing the upstream application's files.

## Version 0.2 additions

Qizhi adds Action Studio: a selected-source learning workflow with a bounded model/tool executor, webpage/text/PDF snapshots, quotation validation, editable draft cards, explicit confirmation, atomic idempotent task creation, run checkpoints, cancellation/retry and endpoint-specific Keychain credentials. These additions use the upstream app's task system and visual foundations. The offline example and new deterministic/HTTP/native integration checks are separately identified; they are not live model or user-study results. See ACTION_STUDIO.md and ACTION_VALIDATION.md.

## Identity configuration

The machine-readable personal identity is in project.json. The application uses Sources/HangLaterCore/AppIdentity.swift. The Chrome manifest's public key fixes the extension ID, and the integration checks ensure the extension, Python host and Swift bridge agree.

The development private key used only to generate that public identity is not retained or distributed. The public manifest key is not an authentication credential.

## Redistribution

Keep LICENSE and THIRD_PARTY_NOTICES.md when redistributing source or binaries. The app build bundles both notices and this origin document into its Resources directory.
