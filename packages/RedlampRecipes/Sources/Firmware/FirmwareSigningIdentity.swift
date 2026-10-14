import Foundation
import Security

/// The Team ID of the running code's own signature, one of the three inputs to the firmware
/// model's inner key (`FirmwareModelKey`). Binding the key to the signature means a patched or
/// re-signed copy of the app derives a different key and can't open the hosted file.
enum FirmwareSigningIdentity {
    /// The Team ID of the running code, only when its signature is valid and an Apple-issued
    /// certificate of that team made it; nil for an unsigned or ad-hoc build (a build from
    /// source), whose model comes from the folder rather than the hosted file. The code-signing
    /// API is the Mac's only, so elsewhere (RedlampRecipes builds for iOS too) it's always nil.
    static func current() -> String? {
        #if os(macOS)
            var code: SecCode?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
            var staticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess,
                let signing = info as? [String: Any],
                let team = signing[kSecCodeInfoTeamIdentifier as String] as? String,
                team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil
            else { return nil }
            // The Team ID is only what the signature claims: it counts once the signature is valid
            // under a certificate Apple issued to that team, which an ad-hoc signature can't be.
            // Both the running code (as the kernel loaded it) and the bundle on disk, frameworks
            // included.
            var requirement: SecRequirement?
            let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString
            guard SecRequirementCreateWithString(text, [], &requirement) == errSecSuccess, let requirement,
                  SecCodeCheckValidity(code, [], requirement) == errSecSuccess,
                  SecStaticCodeCheckValidity(
                      staticCode, SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate), requirement,
                  ) == errSecSuccess
            else { return nil }
            return team
        #else
            return nil
        #endif
    }
}
