import Foundation

extension ConfigLoader {
    static func tomlConfigString(from config: SpacemapConfig, includeHeaderComments: Bool) -> String {
        var lines: [String] = []
        if includeHeaderComments {
            lines += [
                "# Spacemap config",
                ""
            ]
        }

        lines.append("[grid]")
        // `showThumbnailWallpaper` is a grid field but its line lives under
        // [behavior] below, where the writer has always put it.
        for field in ConfigSchema.gridFields where field.key != "showThumbnailWallpaper" {
            lines.append(field.encodeLine(from: config))
        }
        lines += [
            "",
            "[spaceNames]",
            "showSpaceNames = \(config.showSpaceNames)",
            "namingMode = \(tomlString(config.namingMode.rawValue))",
            "autoNameAppCount = \(config.autoNameAppCount)",
            "",
            "[spaceNames.names]"
        ]
        for key in config.spaceNames.keys.sorted() {
            if let name = config.spaceNames[key] {
                lines.append("\(tomlString(String(key))) = \(tomlString(name))")
            }
        }

        lines += ["", "[appearance]"]
        for field in ConfigSchema.appearanceFields {
            lines.append(field.encodeLine(from: config))
        }
        lines += ["", "[behavior]"]
        for field in ConfigSchema.behaviorFields {
            lines.append(field.encodeLine(from: config))
        }
        // Table-shaped keys: the header is `[section.key]`, or `[key]` for a
        // root table such as `[hudKeys]`.
        for field in ConfigSchema.tableFields {
            let header = field.section == field.key ? field.key : "\(field.section).\(field.key)"
            lines += ["", "[\(header)]", field.encodeBody(from: config)]
        }

        lines += ["", "[glyphStrip]"]
        let glyphStrip = config.glyphStrip
        lines += [
            "enabled = \(glyphStrip.enabled)",
            "hideInFullscreen = \(glyphStrip.hideInFullscreen)",
            "theme = \(tomlString(glyphStrip.theme))",
            "showSpaceNumbers = \(glyphStrip.showSpaceNumbers)",
            "spaceLabelStyle = \(tomlString(glyphStrip.spaceLabelStyle.rawValue))",
            "showLayoutSuffix = \(glyphStrip.showLayoutSuffix)",
            "showBSPLayoutBadge = \(glyphStrip.showBSPLayoutBadge)",
            "showStackLayoutBadge = \(glyphStrip.showStackLayoutBadge)",
            "showFloatLayoutBadge = \(glyphStrip.showFloatLayoutBadge)",
            "autoResizeMaxLength = \(glyphStrip.autoResizeMaxLength)",
            "verticalPadding = \(glyphStrip.verticalPadding)",
            "showAppIcons = \(glyphStrip.showAppIcons)",
            "iconSource = \(tomlString(glyphStrip.iconSource.rawValue))",
            "dedupeAppsPerSpace = \(glyphStrip.dedupeAppsPerSpace)",
            "maxIconsPerSpace = \(glyphStrip.maxIconsPerSpace)",
            "iconSize = \(glyphStrip.iconSize)",
            "indexSize = \(glyphStrip.indexSize)",
            "highlightCurrentSpace = \(glyphStrip.highlightCurrentSpace)",
            "backgroundMaterial = \(tomlString(glyphStrip.backgroundMaterial.rawValue))",
            "glassStyle = \(tomlString(glyphStrip.glassStyle.rawValue))",
            "glassClearVariant = \(glyphStrip.glassClearVariant)",
            "glassRegularVariant = \(glyphStrip.glassRegularVariant)",
            "glassTintedVariant = \(glyphStrip.glassTintedVariant)",
            "glassTintedMaterial = \(tomlString(glyphStrip.glassTintedMaterial.rawValue))",
            "matchHUDAppearance = \(glyphStrip.matchHUDAppearance)",
            "backgroundOpacity = \(glyphStrip.backgroundOpacity)",
            "matchBackgroundOpacity = \(glyphStrip.matchBackgroundOpacity)",
            "glassClearOpacity = \(glyphStrip.glassClearOpacity)",
            "glassRegularOpacity = \(glyphStrip.glassRegularOpacity)",
            "glassTintedOpacity = \(glyphStrip.glassTintedOpacity)",
            "solidOpacity = \(glyphStrip.solidOpacity)",
            "cornerRadius = \(glyphStrip.cornerRadius)",
            "margin = \(glyphStrip.margin)",
            "plainMargin = \(glyphStrip.plainMargin)",
            "padding = \(glyphStrip.padding)",
            "lockPadding = \(glyphStrip.lockPadding)",
            "horizontalPadding = \(glyphStrip.horizontalPadding)",
            "displayMode = \(tomlString(glyphStrip.displayMode.rawValue))",
            "iconSpacing = \(glyphStrip.iconSpacing)",
            "indexPadding = \(glyphStrip.indexPadding)",
            "hoverPadding = \(glyphStrip.hoverPadding)",
            "hoverCornerRadius = \(glyphStrip.hoverCornerRadius)",
            "showDisplaySeparators = \(glyphStrip.showDisplaySeparators)",
            "showAddSpaceButton = \(glyphStrip.showAddSpaceButton)",
            "showPlaceholders = \(glyphStrip.showPlaceholders)",
            "leftClickAction = \(tomlString(glyphStrip.leftClickAction.rawValue))",
            "rightClickAction = \(tomlString(glyphStrip.rightClickAction.rawValue))",
            "middleClickAction = \(tomlString(glyphStrip.middleClickAction.rawValue))",
            "position = \(tomlString(glyphStrip.position.rawValue))",
            "plainPosition = \(tomlString(glyphStrip.plainPosition.rawValue))",
            "orientation = \(tomlString(glyphStrip.orientation.rawValue))",
            "verticalLayout = \(tomlString(glyphStrip.verticalLayout.rawValue))",
            "lockPosition = \(glyphStrip.lockPosition)",
            "customX = \(glyphStrip.customX)",
            "customY = \(glyphStrip.customY)",
            "customScreen = \(tomlString(glyphStrip.customScreen))",
            "plainCustomX = \(glyphStrip.plainCustomX)",
            "plainCustomY = \(glyphStrip.plainCustomY)",
            "plainCustomScreen = \(tomlString(glyphStrip.plainCustomScreen))",
            "borderEnabled = \(glyphStrip.borderEnabled)"
        ]

        let appFont = config.appFont
        lines += [
            "",
            "[appFont]",
            "updateMode = \(tomlString(appFont.updateMode.rawValue))",
            "installedVersion = \(tomlString(appFont.installedVersion))",
            "lastCheck = \(appFont.lastCheck)"
        ]

        let profiles = config.spaceNameProfiles
        let activeProfileIndex = config.activeSpaceNameProfileIndex
        let defaultProfile = SpaceNameProfile.default
        let hasNonDefaultProfiles = profiles.count != 1 ||
            profiles.first?.name != defaultProfile.name ||
            !(profiles.first?.spaceNames.isEmpty ?? true)

        if hasNonDefaultProfiles {
            // Indexed-dotted tables only: the document parser supports flat
            // `[a.b]` tables but neither `[[array]]` nor inline `{...}` maps,
            // so profiles must be written in a form the reader parses back.
            // Reader: TOMLConfigDecoder indexed-schema block. Active profile
            // is the `activeIndex` int; out-of-range heals to 0 on load.
            lines += ["", "[spaceNameProfiles]", "activeIndex = \(activeProfileIndex)"]
            for (i, profile) in profiles.enumerated() {
                lines += ["", "[spaceNameProfiles.\(i)]", "name = \(tomlString(profile.name))"]
                if !profile.spaceNames.isEmpty {
                    lines += ["", "[spaceNameProfiles.\(i).names]"]
                    for key in profile.spaceNames.keys.sorted() {
                        if let name = profile.spaceNames[key] {
                            lines.append("\(tomlString(String(key))) = \(tomlString(name))")
                        }
                    }
                }
            }
        }

        lines += ["", "[advanced]"]
        for field in ConfigSchema.advancedFields {
            lines.append(field.encodeLine(from: config))
        }
        return lines.joined(separator: "\n") + "\n"
    }


    static func tomlString(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: escaped += "\\b"
            case 0x09: escaped += "\\t"
            case 0x0A: escaped += "\\n"
            case 0x0C: escaped += "\\f"
            case 0x0D: escaped += "\\r"
            case 0x22: escaped += "\\\""
            case 0x5C: escaped += "\\\\"
            // U+2028/U+2029 split lines for many readers; escape them so a
            // label containing one still round-trips through this parser.
            case 0x2028: escaped += "\\u2028"
            case 0x2029: escaped += "\\u2029"
            case 0x00...0x1F, 0x7F:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }

    static func tomlStringArray(_ values: [String]) -> String {
        "[" + values.map(tomlString).joined(separator: ", ") + "]"
    }

    static func cellStyleName(_ style: CellStyle) -> String {
        switch style {
        case .rects: return "rects"
        case .hybrid: return "hybrid"
        case .icons: return "icons"
        case .thumbnails: return "thumbnails"
        case .simple: return "simple"
        }
    }
}
