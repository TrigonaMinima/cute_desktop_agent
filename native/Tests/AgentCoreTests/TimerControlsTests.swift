import Testing
@testable import AgentCore

// The timer row's geometry — [button][remaining][total] laid out above the avatar —
// is the single source three call sites in AgentApp must agree on: AvatarView.render
// (draws it), AppDelegate.updateHitTest (accepts click-through events over it), and
// AppDelegate's mouseDown routing (button-tap vs. drag-start). Pinning it here in
// AgentCore, with no AppKit dependency, is what makes it unit-testable at all.
struct TimerControlsTests {
    private let position = Point(x: 500, y: 400)
    private let size = Size(width: 78, height: 62)

    // MARK: - Row sits above the avatar

    @Test func timerControlRect_sitsAboveTheAvatarsTopEdge() {
        let button = timerControlRect(position: position, size: size)
        #expect(button.origin.y + button.size.height <= position.y)
    }

    @Test func timerControlRect_leftAlignedWithAvatar() {
        let button = timerControlRect(position: position, size: size)
        #expect(button.origin.x == position.x)
    }

    // MARK: - Left-to-right, non-overlapping slots

    @Test func timerRemainingRect_sitsToTheRightOfTheButtonWithNoOverlap() {
        let button = timerControlRect(position: position, size: size)
        let remaining = timerRemainingRect(position: position, size: size)
        #expect(remaining.origin.x >= button.origin.x + button.size.width)
    }

    @Test func timerRemainingRect_sharesTheButtonsTopEdge() {
        let button = timerControlRect(position: position, size: size)
        let remaining = timerRemainingRect(position: position, size: size)
        #expect(remaining.origin.y == button.origin.y)
    }

    @Test func timerTotalRect_sitsToTheRightOfRemainingWithNoOverlap() {
        let remaining = timerRemainingRect(position: position, size: size)
        let total = timerTotalRect(position: position, size: size)
        #expect(total.origin.x >= remaining.origin.x + remaining.size.width)
    }

    // MARK: - Interactive union (what updateHitTest checks)

    @Test func timerInteractiveRect_containsTheFullAvatarBox() {
        let interactive = timerInteractiveRect(position: position, size: size)
        #expect(isWithin(point: position, rect: interactive))
        let bottomRight = Point(x: position.x + size.width, y: position.y + size.height)
        #expect(isWithin(point: bottomRight, rect: interactive))
    }

    @Test func timerInteractiveRect_containsTheEntireRow() {
        let interactive = timerInteractiveRect(position: position, size: size)
        let button = timerControlRect(position: position, size: size)
        let total = timerTotalRect(position: position, size: size)
        #expect(isWithin(point: button.origin, rect: interactive))
        let totalBottomRight = Point(x: total.origin.x + total.size.width, y: total.origin.y + total.size.height)
        #expect(isWithin(point: totalBottomRight, rect: interactive))
    }

    // MARK: - isWithin classification (button tap vs. drag-start / avatar body)

    @Test func isWithin_pointInsideButtonRect_classifiesInside() {
        let button = timerControlRect(position: position, size: size)
        let center = Point(x: button.origin.x + button.size.width / 2, y: button.origin.y + button.size.height / 2)
        #expect(isWithin(point: center, rect: button))
    }

    @Test func isWithin_pointOnAvatarBody_isNotInsideTheButtonRect() {
        let button = timerControlRect(position: position, size: size)
        let bodyCenter = Point(x: position.x + size.width / 2, y: position.y + size.height / 2)
        #expect(!isWithin(point: bodyCenter, rect: button))
    }
}
