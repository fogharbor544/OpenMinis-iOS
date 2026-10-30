"""Source contract checks; these do not substitute for Swift or device tests."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

class ChatSettingsContracts(unittest.TestCase):
    def test_title_uses_navigation_pane_and_invalidates_toolbar_on_resize(self):
        title = read("Views/Chat/AIChatView/AIChatView+NavigationTitle.swift")
        principal = title.split("var chatNavPrincipalContent:")[1].split("var chatToolbarKey:")[0]
        self.assertNotIn("UIScreen", principal)
        self.assertIn("navigationContainerWidth - 144", principal)
        self.assertIn("containerWidth: navigationContainerWidth", title)
        host = read("Views/Chat/AIChatView/Toolbar/ChatToolbarHost.swift")
        self.assertIn("var containerWidth: CGFloat", host)
        self.assertIn("lhs.key == rhs.key", host)

    def test_complete_composer_measured_and_text_updates_without_debounce(self):
        source = read("Views/Chat/AIChatView/AIChatView+InputBar.swift")
        measurement = source.index(".onGeometryChange(for: CGRect.self)")
        self.assertGreater(measurement, source.index("SwipeToSendHint("))
        self.assertGreater(measurement, source.index("if vm.isSuspended"))
        self.assertIn("if !voiceInputActive", source[measurement:])
        self.assertIn("inputBarHeight = newH", source[measurement:])
        area = read("Views/Chat/AIChatView/AIChatView+MessagesArea.swift")
        self.assertNotIn("hasFloatingPreview ? 80", area)
        self.assertIn("inputBarHeight + floatingBarHeight + 12", area)

    def test_user_drag_is_not_replaced_by_auto_follow(self):
        source = read("Agent/MessageList/CollectionViewMessageListV3/CollectionViewMessageListV3.swift")
        self.assertIn("if !cv.isTracking && !cv.isDragging && !cv.isDecelerating,", source)
        self.assertIn("coord.scrollMode == .autoScrolling || wasNearBottomBefore", source)

    def test_bot_chat_push_and_reduced_motion(self):
        source = read("Views/ContentView/Bots/BotWorkspaceView.swift")
        main = source.split("struct BotProfileEditor")[0]
        self.assertNotIn(".sheet(item: $chat)", main)
        self.assertIn(".navigationDestination(isPresented:", main)
        self.assertIn("UIImpactFeedbackGenerator(style: .light).impactOccurred()", main)
        self.assertIn("configuration.isPressed && !reduceMotion", source)
        home = read("Views/ContentView/ContentView+SessionList.swift")
        self.assertIn("animated: !UIAccessibility.isReduceMotionEnabled", home)

    def test_one_permission_center_preserves_generic_helpers(self):
        source = read("Views/Settings/OffloadPermissionSettingsView.swift")
        self.assertIn("BuiltinCapabilitiesView()", source)
        self.assertNotIn("CommandPermissionRow", source)
        self.assertNotIn("setPermissionLevel", source)
        runtime = read("Views/Settings/SettingsSheet.swift")
        self.assertIn("HelperSettingsView()", runtime)
        capabilities = read("Views/MCP/MCPIntegrationsView.swift")
        self.assertIn(".listStyle(.insetGrouped)", capabilities)
        self.assertIn('("location",', capabilities)
        self.assertIn('("clipboard",', capabilities)
        self.assertIn("checkmark.circle.fill", capabilities)

    def test_permission_chinese_and_no_commander_backup_claim(self):
        catalog = json.loads(read("Localizable.xcstrings"))["strings"]
        for key in ["Ask Once Per Session", "Action", "arg", "Permission Request",
                    "Steps, heart rate, sleep, and other health records"]:
            self.assertTrue(catalog[key]["localizations"]["zh-Hans"]["stringUnit"]["value"])
        self.assertFalse(any("commander" in key.lower() for key in catalog))

if __name__ == "__main__":
    unittest.main()
