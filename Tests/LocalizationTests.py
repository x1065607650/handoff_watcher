"""Checks real Bundle language selection in separate processes, without changing user preferences."""
import json
import pathlib
import re
import subprocess
import sys

executable, root = sys.argv[1], pathlib.Path(sys.argv[2])
def probe(languages, *extra):
    return json.loads(subprocess.check_output([executable, '--probe', '-AppleLanguages', languages, *extra], text=True))

cases = [
    ('(en)', 'Services OK'),
    ('("en-GB")', 'Services OK'),
    ('("zh-Hans")', '服务正常'),
    ('("zh-CN")', '服务正常'),
    ('(fr)', 'Services OK'),
    ('(fr, "zh-Hans", en)', '服务正常'),
    ('(en, "zh-Hans")', 'Services OK'),
]
for languages, expected in cases:
    result = probe(languages)
    assert result['healthy'] == expected, (languages, result)
    assert result['running'] == ('运行中' if expected == '服务正常' else 'Running'), result
    assert result['error'] == ('检查超时' if expected == '服务正常' else 'Check timed out'), result
    print('PASS: Bundle language preferences', languages)

for locale in ['en_US', 'zh_CN']:
    twelve = probe('(en)', '-AppleLocale', locale + '@hours=h12')['time']
    twenty_four = probe('(en)', '-AppleLocale', locale + '@hours=h23')['time']
    assert twelve != twenty_four, (locale, twelve, twenty_four)
    assert re.search(r'\d{1,2}:\d{2}:\d{2}', twelve) and re.search(r'\d{1,2}:\d{2}:\d{2}', twenty_four), (twelve, twenty_four)
    print('PASS: Locale hour-cycle preferences and seconds', locale, twelve, twenty_four)

source = '\n'.join(p.read_text() for p in (root / 'Sources').glob('*.swift'))
assert not re.search(r'[\u4e00-\u9fff]', source), 'Hard-coded Chinese found in Swift source'
keys = set(re.findall(r'^"([^"]+)"\s*=', (root / 'Resources/en.lproj/Localizable.strings').read_text(), re.M))
referenced = set(re.findall(r'(?:L10n\.text|localizer\.text)\("([^"]+)"', source))
referenced |= set(re.findall(r'"((?:error|qa)\.[a-z_]+)"', source))
assert referenced <= keys, referenced - keys
print('PASS: All referenced localization keys exist; no hard-coded Chinese')
print('Localization integration checks passed')
