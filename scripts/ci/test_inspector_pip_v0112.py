from pathlib import Path
import sys
r=Path(__file__).resolve().parents[2]
app=r/'SolidSecViewer'
get=lambda f:(app/f).read_text()
version=(r/'SolidSecViewer.xcodeproj/project.pbxproj').read_text()
checks={
'PiP only plain explorer': 'allowsPictureInPicture: true' in get('NikaidoRegularVideoPlayer.swift') and 'allowsPictureInPicture: true' not in get('NikaidoSecureVideoView.swift'),
'PiP not encrypted': 'var allowsPictureInPicture = false' in get('NikaidoSecureVideoView.swift'),
'media types scoped': 'startAccessingSecurityScopedResource' in get('NikaidoRegularVideoPlayer.swift'),
'Binary inspector read-only': 'inspectMachO' in get('NikaidoBinaryInspector.swift') and 'inspectZIP' in get('NikaidoBinaryInspector.swift'),
'Background media allowed': 'UIBackgroundModes' in get('Info.plist'),
'PBX binary unique': version.count('NikaidoBinaryInspector.swift in Sources')>=1 and version.count('NikaidoRegularVideoPlayer.swift in Sources')>=1,
'Version updated': version.count('MARKETING_VERSION = 0.11.2;')==2 and version.count('CURRENT_PROJECT_VERSION = 33;')==2
}
for k,v in checks.items():print(('OK ' if v else 'FAIL ')+k)
if not all(checks.values()):sys.exit(1)
