import re
#!/usr/bin/env python3
"""Protection against accidental disclosure in app snapshots / recording."""
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[2]
a=(root/"SolidSecViewer/ContentView.swift").read_text()
b=(root/"SolidSecViewer/PrivacyShield.swift").read_text()
p=(root/"SolidSecViewer.xcodeproj/project.pbxproj").read_text()
checks={
    "scene deactivation covered immediately": "UIScene.willDeactivateNotification" in a and "PrivacyShield.show()" in a,
    "app lifecycle snapshot protection": "UIApplication.willResignActiveNotification" in a and "UIApplication.didEnterBackgroundNotification" in a,
    "protected data loss locks vault": "UIApplication.protectedDataWillBecomeUnavailableNotification" in a and "lockForPrivacy()" in a,
    "screen recording privacy": "UIScreen.capturedDidChangeNotification" in a and "PrivacyShield.isScreenCaptureActive()" in a,
    "screenshot only post-capture": "UIApplication.userDidTakeScreenshotNotification" in a and "AFTER iOS has already saved" in a,
    "no arbitrary screenshot delay": "asyncAfter(deadline: .now() + 0.6)" not in a,
    "key and streams invalidated": "privateVault.lock()" in a and ".nikaidoForceStopLink" in a,
    "blocking cover not just blur": "view.backgroundColor = .black" in b and "view.isUserInteractionEnabled = true" in b,
    "cover readable to accessibility": "view.accessibilityViewIsModal = true" in b,
    "screen capture checked at launch": "if PrivacyShield.isScreenCaptureActive()" in a,
    "version advanced at least": (len(re.findall(r"MARKETING_VERSION = (\d+)\.(\d+)\.(\d+);", p)) == 2 and all(tuple(map(int, v)) >= (0, 11, 5) for v in re.findall(r"MARKETING_VERSION = (\d+)\.(\d+)\.(\d+);", p)) and len(re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", p)) == 2 and all(int(v) >= 36 for v in re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", p))),
}
for k,v in checks.items():print(("OK " if v else "FAIL ")+k)
if not all(checks.values()):sys.exit(1)
