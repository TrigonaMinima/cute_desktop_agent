import Testing
@testable import AgentCore

// LoginItemStatus mirrors SMAppService.Status (kept AppKit/ServiceManagement-free so it
// stays here in AgentCore, Foundation-only and unit-testable) — a four-state enum, not a
// boolean. The naive `status == .enabled` mapping silently no-ops for a user stuck in
// `.requiresApproval` (registered, but the OS is waiting on them to approve it in System
// Settings): the toggle would show "off" and clicking it again would do nothing new. These
// tests pin the presentation for all four states so that gap can't reappear unnoticed.
struct LoginItemPresentationTests {

    @Test func enabled_showsCheckedAndEnabled() {
        let presentation = loginItemPresentation(for: .enabled)
        #expect(presentation.title == "Launch at Login")
        #expect(presentation.isChecked == true)
        #expect(presentation.isEnabled == true)
        #expect(presentation.opensSystemSettings == false)
    }

    @Test func notRegistered_showsUncheckedAndEnabled() {
        let presentation = loginItemPresentation(for: .notRegistered)
        #expect(presentation.title == "Launch at Login")
        #expect(presentation.isChecked == false)
        #expect(presentation.isEnabled == true)
        #expect(presentation.opensSystemSettings == false)
    }

    @Test func requiresApproval_hintsAtSettingsAndOpensThem() {
        let presentation = loginItemPresentation(for: .requiresApproval)
        #expect(presentation.title == "Launch at Login (Approve in Settings…)")
        #expect(presentation.isChecked == false)
        #expect(presentation.isEnabled == true)
        #expect(presentation.opensSystemSettings == true)
    }

    @Test func notFound_isDisabled() {
        let presentation = loginItemPresentation(for: .notFound)
        #expect(presentation.title == "Launch at Login (Unavailable)")
        #expect(presentation.isChecked == false)
        #expect(presentation.isEnabled == false)
        #expect(presentation.opensSystemSettings == false)
    }
}
