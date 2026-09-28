"""Validates distributable resources and read-only CLI localization; never restarts services."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile

root = Path(sys.argv[1])
app = root / 'outputs/HandoffWatcher.app'
archive = root / 'outputs/HandoffWatcher-macOS27-arm64.zip'
if not app.exists() or not archive.exists():
    print('Package checks skipped: run ./build.sh first')
    sys.exit(0)
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleDevelopmentRegion'] == 'en'
assert info['CFBundleLocalizations'] == ['en', 'zh-Hans']
assert info['CFBundleIdentifier'] == 'local.relay.app', 'Release must not use preview identity'
with zipfile.ZipFile(archive) as package:
    assert package.read('HandoffWatcher.app/Contents/Info.plist') == (app / 'Contents/Info.plist').read_bytes()
    for language in ['en', 'zh-Hans']:
        for name in ['Localizable.strings', 'InfoPlist.strings']:
            relative = Path(language + '.lproj') / name
            expected = (root / 'Resources' / relative).read_bytes()
            assert (app / 'Contents/Resources' / relative).read_bytes() == expected
            assert package.read('HandoffWatcher.app/Contents/Resources/' + str(relative)) == expected
    with tempfile.TemporaryDirectory(prefix='handoff-watcher-verify-') as directory:
        package.extractall(directory)
        binary = Path(directory) / 'HandoffWatcher.app/Contents/MacOS/HandoffWatcher'
        binary.chmod(0o755)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(Path(directory) / 'HandoffWatcher.app')], check=True)
print('PASS: Release identity, localization resources, ZIP contents and signature')
executable = app / 'Contents/MacOS/HandoffWatcher'
for language, labels in [('en', {'Running', 'Idle'}), ('zh-Hans', {'运行中', '待命'}), ('fr', {'Running', 'Idle'})]:
    result = subprocess.run([str(executable), '--diagnose', '-AppleLanguages', f'("{language}")'], capture_output=True, text=True)
    assert result.returncode in (0, 1), result.stderr
    data = json.loads(result.stdout)
    assert set(data) == {'services', 'error'}
    assert len(data['services']) == 3
    for service in data['services']:
        assert set(service) == {'name', 'healthy', 'detail', 'pid'}
        assert isinstance(service['healthy'], bool)
        if service['healthy']:
            assert service['detail'] in labels, (language, service)
    print('PASS: Packaged read-only CLI localization', language)
