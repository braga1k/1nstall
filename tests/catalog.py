"""Cross-platform catalog checks: python tests/catalog.py (no installs)."""
import csv
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

root = Path(__file__).resolve().parents[1]
apps = json.loads((root / 'catalog.json').read_text(encoding='utf-8-sig'))
profiles = json.loads((root / 'profiles.json').read_text(encoding='utf-8-sig'))
by_key = {app['Key']: app for app in apps}
by_name = {app['Name']: app for app in apps}
assert apps and len(by_key) == len(apps) == len(by_name), 'Duplicate or empty catalog'
taxonomy = json.loads((root / 'docs/CATEGORY-TAXONOMY.json').read_text())
categories = {category['Name'] for category in taxonomy['Categories']}
assert len(categories) == 24 and len(taxonomy['Groups']) == 4
ids = []
for app in apps:
    assert app['Category'] in categories, app['Name']
    assert app['Category'] in taxonomy['Groups'][app['CategoryGroup']], app['Name']
    assert len(set(app['AlsoIn'])) == len(app['AlsoIn']), app['Name']
    assert set(app['AlsoIn']) <= categories - {app['Category']}, app['Name']
    assert app['Name'] and app['Description'], app['Key']
    assert bool(app['Ids']) != bool(app['Url']), app['Name']
    for package in app['Ids']:
        assert re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.+_-]*', package), package
        ids.append(package.casefold())
    if app['Url']:
        url = urlsplit(app['Url'])
        assert url.scheme == 'https' and url.netloc, app['Name']
    assert all(key in by_key for key in app['Requires']), app['Name']
assert len(set(ids)) == len(ids), 'Duplicate WinGet package IDs'
assert len(profiles) == len({p['Key'] for p in profiles}) == 20
assert {p['Group'] for p in profiles} == {'Everyday & Work', 'Create', 'Files & Privacy', 'PC & Tools'}
assert {'essentials','creator','gaming','development','office','audio','3d','opensource'} <= {p['Key'] for p in profiles}
for profile in profiles:
    assert profile['Name'] and profile['Description'] and 8 <= len(profile['Apps']) <= 11
    assert len(set(profile['Apps'])) == len(profile['Apps']), profile['Name']
    assert all(key in by_key for key in profile['Apps']), profile['Name']

assert 'flstudio' not in next(p for p in profiles if p['Key'] == 'audio')['Apps']
assert 'ts3' not in next(p for p in profiles if p['Key'] == 'gaming')['Apps']

# Representative mistakes from the category review must not recur.
for name, expected in {'1Password': 'Security & Privacy', 'OneDrive': 'Cloud & Backup',
                       'Paint.NET': 'Design & Photography', 'Hugo': 'Development',
                       'ChatGPT Desktop': 'AI Tools', 'AnyDesk': 'Remote Access',
                       'Spotify': 'Media Players', 'Krita': 'Design & Photography',
                       'UltiMaker Cura': '3D & CAD', 'Logi Options+': 'Hardware & Drivers',
                       'DaVinci Resolve': 'Video Editing', 'Equalizer APO': 'Audio Controls'}.items():
    assert by_name[name]['Category'] == expected, name
assert 'Video Editing' in by_name['Blender']['AlsoIn']
assert 'Audio Production' in by_name['Adobe Creative Cloud']['AlsoIn']
for category in taxonomy['Categories']:
    assert category['PrimaryApps'] == sum(a['Category'] == category['Name'] for a in apps)
    assert category['VisibleApps'] == sum(a['Category'] == category['Name'] or category['Name'] in a['AlsoIn'] for a in apps)
with (root / 'docs/CATEGORY-AUDIT.csv').open(encoding='utf-8-sig', newline='') as file:
    review = list(csv.DictReader(file))
assert len(review) == len({r['CatalogKey'] for r in review}) == len(apps)
for row in review:
    app = by_key[row['CatalogKey']]
    assert (row['Application'], row['Category'], row['Group']) == (app['Name'], app['Category'], app['CategoryGroup'])
with (root / 'docs/CATEGORY-COVERAGE.csv').open(encoding='utf-8-sig', newline='') as file:
    coverage = list(csv.DictReader(file))
benchmark = json.loads((root / 'docs/CATEGORY-COVERAGE.json').read_text())
assert len(coverage) == benchmark['Rows']
assert {r['Category'] for r in coverage} == categories
for category in benchmark['Categories']:
    rows = [r for r in coverage if r['Category'] == category['Category']]
    assert len(rows) == category['Reviewed'] <= 50
    assert len({r['Application'].casefold() for r in rows}) == len(rows)
    assert [int(r['Position']) for r in rows] == list(range(1, len(rows) + 1))
    assert sum(r['Presence'] == 'Missing' for r in rows) == category['Missing']
for row in coverage:
    if row['Presence'] == 'Present':
        app = by_key[row['CatalogKey']]
        assert row['Category'] == app['Category'] or row['Category'] in app['AlsoIn']
    if row['EvidenceType'] == 'Publisher page reviewed':
        assert urlsplit(row['EvidenceURL']).scheme == 'https'

with (root / 'docs/DAILY-USE-AUDIT.csv').open(encoding='utf-8-sig', newline='') as file:
    audit = list(csv.DictReader(file))
assert len(audit) == len({row['Application'] for row in audit}) == 200
for row in audit:
    assert row['CatalogKey'] in by_key, row['Application']
    app = by_key[row['CatalogKey']]
    assert row['ActualCategory'] == app['Category'], row['Application']
    assert row['EvidenceURL'] and row['EvidenceType'], row['Application']
    if row['CatalogStatus'] == 'Covered by suite':
        assert app['Name'] == 'Adobe Creative Cloud', row['Application']
        assert row['Application'].removeprefix('Adobe ') in app['Description'], row['Application']
    else:
        assert row['Application'] == app['Name'], row['Application']
summary = json.loads((root / 'docs/CATALOG-AUDIT.json').read_text())
assert summary['CatalogTotal'] == len(apps)
assert summary['Automatic'] == sum(bool(app['Ids']) for app in apps)
assert summary['Guided'] == sum(bool(app['Url']) for app in apps)
assert summary['CategoryCounts'] == {c: sum(a['Category'] == c for a in apps) for c in categories}
print(f'PASS: {len(apps)} apps, {len(categories)} categories, unique safe package IDs, '
      f'{len(profiles)} profiles, all 200 shortlist mappings and {len(coverage)} benchmark rows')
