#!/usr/bin/env python3
"""Static safeguards for v0.11.1: no plaintext video progress or automatic import deletion."""
from pathlib import Path
import sys
import re
root = Path(__file__).resolve().parents[2]
app = root / 'SolidSecViewer'
read = lambda name: (app / name).read_text(encoding='utf-8')
player = read('NikaidoSecureVideoView.swift')
drag = read('ExplorerDragMove.swift')
explorer = read('ExplorerView.swift')
content = read('ContentView.swift')
vault = read('PrivateVaultView.swift')
info = read('Info.plist')
pbx = (root / 'SolidSecViewer.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
checks = {
    'video model compiled': 'NikaidoSecureVideoView.swift in Sources' in pbx and 'A930' in pbx,
    'video progress in keychain': 'SecItemAdd' in player and 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' in player,
    'video identifier opaque and stable': 'SHA256.hash' in player and 'stableID(for url:' in player,
    'video speed control': 'playImmediately(atRate:' in player and '1.5' in player,
    'vault video playback still invalidates on lock': '.nikaidoVaultDidLock' in vault and 'stopVideoPlayback(playback)' in vault,
    'drag edge ticker cancels': 'CADisplayLink' in drag and 'setActive(false)' in drag and 'scroll.setContentOffset' in drag,
    'drag probe installed in two panes': explorer.count('ExplorerDragEdgeScroll(state: dragState)') == 2,
    'VoiceOver has file actions': 'accessibilityAction(named: "Abrir o seleccionar")' in explorer,
    'incoming file needs explicit choice': 'confirmationDialog(' in content and 'importIncomingDocument(intoVault: false)' in content,
    'incoming import copies, no auto delete': 'ExplorerFileEngine.importFile(' in content and 'privateVault.importFiles(' in content,
    'document handoff registered': 'CFBundleDocumentTypes' in info and 'LSItemContentTypes' in info,
    'version not downgraded': (len(re.findall(r'MARKETING_VERSION = (\\d+)\\.(\\d+)\\.(\\d+);', pbx)) == 2 and all(tuple(map(int, v)) >= (0, 11, 1) for v in re.findall(r'MARKETING_VERSION = (\\d+)\\.(\\d+)\\.(\\d+);', pbx)) and len(re.findall(r'CURRENT_PROJECT_VERSION = (\\d+);', pbx)) == 2 and all(int(v) >= 32 for v in re.findall(r'CURRENT_PROJECT_VERSION = (\\d+);', pbx))),
}
for name, ok in checks.items():
    print(('OK   ' if ok else 'FAIL ') + name)
if not all(checks.values()):
    sys.exit(1)
print('ACCESSIBILITY / VIDEO / DRAG / IMPORT GUARDS: OK')
