import Foundation
import RedlampEngineAPI

extension LightroomConverter {
    private typealias PhotoNote = LightroomPhoto.Note
    private typealias Reason = LightroomImportReport.Reason

    /// A photo's settings carried over to its whole edit's, by EDT-11's table and what it says of photos.
    init(_ settings: CameraRawSettings, photo: LightroomPhotoContext) {
        self.settings = settings
        self.photo = photo
        process = LightroomPhoto.Process(settings.text("ProcessVersion"))
        for (key, rule) in LightroomPreset.orderedSettings(settings) {
            applyPhoto(rule, to: key)
        }
        setSplitToningBlending()
        setOrientation(photo)
    }

    private mutating func applyPhoto(_ rule: LightroomRule?, to key: String) {
        if process.isEarlier {
            if LightroomPhoto.laterTone.contains(key) {
                return
            }
            if case let .parameter(spec)? = rule, let control = LightroomPhoto.earlierControl(key, in: process) {
                return leaveOut(key, .earlierProcess, PhotoNote.earlierProcess(control, process), at: spec.defaultValue)
            }
        }
        switch rule {
        case nil where key.hasPrefix("Enable"):
            setPanelSwitch(key)
        case nil:
            applyPhoto(LightroomPhoto.otherRules[key] ?? .leftOut(.unknown, Note.unknown), to: key)
        case let .perPhoto(photoRule, _)?:
            applyPhoto(photoRule, to: key)
        case .whiteBalance?:
            setWhiteBalanceMode(key)
        case let .kelvin(spec)?:
            setTemperature(key, spec)
        case .incremental?:
            setShift(key)
        case .lensProfile?:
            setLensProfile(key)
        case let .colorLuminance(spec)?:
            // Lightroom doesn't apply HSL Luminance to a black-and-white photo, nor the B&W mix to a colour one.
            if !isBlackAndWhite {
                setNumber(key, spec)
            }
        case let .grayMix(spec)?:
            if isBlackAndWhite {
                setNumber(key, spec, approximated: Note.grayMix)
            }
        case let .ignored(note)?:
            leaveOut(key, .notInRedlamp(row: nil), note)
        case let .unlessOff(note, switchKey)?:
            leaveOut(key, .notInRedlamp(row: nil), note, switchedBy: switchKey)
        case let rule?:
            apply(rule, to: key)
        }
    }

    private mutating func applyPhoto(_ rule: LightroomPhotoRule, to key: String) {
        switch rule {
        case .metadata:
            break
        case let .unchecked(spec):
            setNumber(key, spec, remark: isInert(key, at: spec.defaultValue) ? nil : PhotoNote.uncheckedScale)
        case .profile:
            setProfile(key)
        case let .lensProfileAmount(spec):
            setNumber(key, spec)
        case .crop:
            setCrop(key)
        case .upright:
            if let mode = settings.number("PerspectiveUpright"), mode != 0 {
                ignore(key, PhotoNote.upright(LightroomPhoto.uprightModes[Int(mode)]), reason: .notYetChecked)
            }
        case .masks:
            setMasks(key)
        case .spots:
            setSpots(key)
        case .auto:
            if settings.flag(key) == true {
                report(key, .approximated, PhotoNote.auto)
            }
        case let .earlierProcess(control):
            if process.isEarlier {
                leaveOut(key, .earlierProcess, PhotoNote.earlierProcess(control, process))
            }
        case let .leftOut(reason, note, switchKey, inert):
            leaveOut(key, reason, note, at: inert, switchedBy: switchKey)
        }
    }

    /// Leaves a setting out for `reason` while it does something (`isInert`), and while the setting
    /// `switchedBy` names, if any, isn't off.
    private mutating func leaveOut(
        _ key: String,
        _ reason: Reason,
        _ note: String,
        at inert: Double = 0,
        switchedBy switchKey: String? = nil,
    ) {
        guard !isInert(key, at: inert), !(switchKey.map { isInert($0) } ?? false) else { return }
        ignore(key, note, reason: reason)
    }

    /// Whether a photo's setting does nothing: missing, blank, an empty list or array, a structure that's empty
    /// or switched off (`Active` false), off (`False`, `Off`), or `value`.
    private func isInert(_ key: String, at value: Double = 0) -> Bool {
        switch settings[key] {
        case nil:
            return true
        case let .text(text):
            let off = CameraRawSettings.text(text, is: "false") || CameraRawSettings.text(text, is: "off")
            return off || settings.isBlank(key) || settings.number(key) == value
        case let .list(items):
            return items.isEmpty
        case let .structures(items):
            return items.isEmpty
        case let .structure(fields):
            return fields.values.isEmpty || fields.flag("Active") == false
        }
    }

    // MARK: - White balance

    /// A raw's white balance by name, Auto kept as Custom with the values Lightroom found; a rendered photo's
    /// stays as shot, shifted by Lightroom's relative white balance.
    private mutating func setWhiteBalanceMode(_ key: String) {
        guard let photo, let name = settings.text(key) else { return ignore(key, Note.unreadable) }
        guard let mode = Self.whiteBalanceModes[name] else { return ignore(key, Note.unknownWhiteBalance(name)) }
        guard photo.isRaw else {
            whiteBalanceMode = mode == .auto && !hasIncremental ? .auto : .asShot
            switch mode {
            case .asShot:
                report(key, .mapped)
            case .auto:
                report(key, .approximated, hasIncremental ? PhotoNote.autoShift : PhotoNote.autoMeasured)
            case .custom where hasIncremental:
                report(key, .approximated, Note.incrementalCustom)
            case .custom:
                report(key, .mapped)
            default:
                ignore(key, PhotoNote.notForRendered(name))
            }
            return
        }
        switch mode {
        case .auto where hasKelvin:
            whiteBalanceMode = .custom
            report(key, .approximated, PhotoNote.autoWhiteBalance)
        case .auto:
            whiteBalanceMode = .auto
            report(key, .approximated, PhotoNote.autoMeasured)
        default:
            whiteBalanceMode = mode
            report(key, .mapped)
        }
    }

    /// A raw's Temperature or Tint: Custom's values, or what a named white balance sets.
    private mutating func setTemperature(_ key: String, _ spec: ParameterSpec) {
        guard photo?.isRaw == true else { return }
        guard let value = settings.number(key) else { return ignore(key, Note.unreadable) }
        let mode = settings.text("WhiteBalance").flatMap { Self.whiteBalanceModes[$0] }
        if let mode, mode != .custom, mode != .auto {
            return report(key, .mapped, PhotoNote.setByMode(mode))
        }
        whiteBalanceMode = .custom
        set(spec, value, key: key, keepingDefault: true)
    }

    /// A rendered photo's relative white balance as Red and Blue Shift, unless it's as shot.
    private mutating func setShift(_ key: String) {
        guard photo?.isRaw == false, settings.text("WhiteBalance") != "As Shot" else { return }
        shiftWhiteBalance(key)
    }

    // MARK: - Profile, lens and geometry

    /// The profile's Base Look: the `Look` Lightroom applies when there is one, else `CameraProfile`.
    private mutating func setProfile(_ key: String) {
        guard let photo else { return }
        let look = settings.structure("Look")
        let lookName = look?.text("Name").flatMap { $0.isEmpty ? nil : $0 }
        guard let name = lookName ?? settings.text("CameraProfile"), key == "CameraProfile" || lookName != nil else {
            return
        }
        let profile = LightroomPhoto.profile(name, amount: (look?.number("Amount") ?? 1) * 100, photo: photo)
        baseLook = profile.look
        if key == "CameraProfile", let lookName {
            report(key, profile.outcome, PhotoNote.underLook(lookName))
        } else {
            report(key, profile.outcome, profile.note)
        }
    }

    /// Enable Profile Corrections: the correction the file carries, or a profile from Redlamp's Lens
    /// Profiles folder.
    private mutating func setLensProfile(_ key: String) {
        guard let photo, let enabled = settings.flag(key) else { return ignore(key, Note.unreadable) }
        store(Spec.lensProfile, enabled ? 1 : 0)
        let profile = settings.text("LensProfileName").flatMap { $0.isEmpty ? nil : $0 }
        if !enabled {
            report(key, .mapped)
        } else if photo.hasLensCorrection {
            let isFiles = settings.flag("LensProfileIsEmbedded") != false
            report(key, .mapped, isFiles ? nil : PhotoNote.lensFile(profile))
        } else {
            let file = settings.text("LensProfileFilename").flatMap { $0.isEmpty ? nil : $0 }
            report(key, .approximated, PhotoNote.lensFolder(profile, file: file))
        }
    }

    /// The crop and its angle, in the photo's frame after the camera's and the catalog's orientations.
    private mutating func setCrop(_ key: String) {
        guard let photo else { return }
        guard settings.flag("HasCrop") == true else { return report(key, .mapped) }
        if crop == nil {
            let size = photo.cameraOrientation.swapsAxes
                ? PixelSize(width: photo.size.height, height: photo.size.width) : photo.size
            guard let lightroom = LightroomCrop(settings), let mapped = lightroom.redlampCrop(
                imageSize: size, cameraOrientation: photo.cameraOrientation,
                orientation: photo.orientation ?? .identity,
            ) else { return ignore(key, Note.unreadable) }
            crop = (mapped.crop, mapped.angle)
        }
        guard let catalog = photo.catalogSize else { return report(key, .mapped) }
        let stored = photo.size
        let offset = min(
            max(abs(catalog.width - stored.width), abs(catalog.height - stored.height)),
            max(abs(catalog.width - stored.height), abs(catalog.height - stored.width)),
        )
        if offset == 0 {
            report(key, .mapped)
        } else {
            report(key, .approximated, PhotoNote.frame(catalog, file: stored, offset: offset))
        }
    }

    /// The catalog's rotation and flip, once Lightroom's codes are known; until then its code is reported.
    private mutating func setOrientation(_ photo: LightroomPhotoContext) {
        if let orientation = photo.orientation {
            if !orientation.isIdentity {
                report("orientation", .mapped)
            }
        } else if let code = photo.orientationCode, !code.isEmpty {
            ignore("orientation", PhotoNote.rotation(code), reason: .notYetChecked)
        }
    }

    // MARK: - What's left out

    private mutating func setMasks(_ key: String) {
        guard !isInert(key) else { return }
        guard let corrections = settings.structures(key) else { return ignore(key, Note.unreadable) }
        let masks = corrections.reduce(0) { $0 + LightroomPhoto.count($1.structures("CorrectionMasks") ?? []) }
        ignore(key, PhotoNote.masks(corrections.count, components: masks), reason: .notYetChecked)
    }

    private mutating func setSpots(_ key: String) {
        guard !isInert(key) else { return }
        guard let count = settings.structures(key)?.count ?? settings.list(key)?.count else {
            return ignore(key, Note.unreadable)
        }
        ignore(key, PhotoNote.spots(count), reason: .notYetChecked)
    }

    private mutating func setPanelSwitch(_ key: String) {
        if settings.flag(key) == false {
            ignore(key, PhotoNote.panelSwitch, reason: .notYetChecked)
        }
    }
}
