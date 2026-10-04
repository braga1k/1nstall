"""Offline pack completeness and interpolation checks; no translation service required."""
import json, re
from pathlib import Path

root=Path(__file__).resolve().parents[1]
packs=json.loads((root/'locales.json').read_text(encoding='utf-8-sig'))
required='en zh-Hans hi es ar fr bn pt-PT id ur de it nl da sv nb nn fi is ga mt el pl cs sk hu ro bg hr sl et lv lt sq bs sr sr-Latn sr-Latn-ME rm lb ca be uk ru tr ka hy az kk mk ja'.split()
assert set(packs)==set(required)
assert [code for code in packs if code.startswith('pt')]==['pt-PT']
keys=set(packs['en']['Strings'])
for code,pack in packs.items():
    assert pack['Name'] and isinstance(pack['Rtl'],bool),code
    assert set(pack['Strings'])==keys,code
    for key,value in pack['Strings'].items():
        assert value.strip() and '\ufffd' not in value and 'ZXQ' not in value and not re.search(r'7000\d\d',value),(code,key)
        assert sorted(re.findall(r'\{\d+\}',key))==sorted(re.findall(r'\{\d+\}',value)),(code,key)
print(f'PASS: {len(packs)} locale choices, {len(keys)} strings each, complete keys, preserved placeholders and pt-PT only.')
