#!/usr/bin/env python3
"""Scan release source for private files, obvious credentials, local paths, and PNG metadata.
This is a focused preflight, not a guarantee against every secret or a legal review.

    audit_release.py                       scan the source tree (git-tracked and untracked files)
    audit_release.py --artifact PATH ...   scan built artifacts: .love, .zip, game.data, folders

Ravensight ingest keys (gt_live_, gt_pub_, gt_test_) never belong in source. In an
artifact a public key is expected in exactly two places: analytics.config.lua at the
root of a native .love, and a web build's index.html. Anywhere else is a finding, a
live or test key is always one, and a source zip (a name containing "source") may hold
no key and no analytics.config.lua at all.
"""
import argparse
import io
import re
import struct
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT = {'.lua','.py','.md','.txt','.html','.css','.js','.mjs','.json','.yml','.yaml','.toml','.sh','.rockspec'}
RULES = {
    'private key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'GitHub token': re.compile(rb'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}'),
    'API secret': re.compile(rb'\bsk-(?:proj-)?[A-Za-z0-9_-]{35,}'),
    'AWS access key': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'personal machine path': re.compile(rb'/Users/[A-Za-z0-9._-]+/|C:\\Users\\[^\\]+\\'),
    'removed branding': re.compile(('first'+'mate|stack'+'hawk').encode(),re.I),
    'Ravensight ingest key': re.compile(rb'gt_(?:live|pub|test)_[A-Za-z0-9_-]{16,}'),
}
KEY = RULES['Ravensight ingest key']
CONFIG = 'analytics.config.lua'

PRIVATE = {'.env','.DS_Store','loupe_overrides.lua','config.toml','.loupe-backups','__pycache__'}

def main():
    names=subprocess.check_output(['git','ls-files','-co','--exclude-standard','-z'],cwd=ROOT).split(b'\0')
    findings=[];count=0;images=0
    for raw in sorted(set(names)):
        if not raw:continue
        rel=Path(raw.decode());path=ROOT/rel
        if not path.is_file():continue
        if path.resolve()==Path(__file__).resolve():continue
        count+=1
        if path.is_symlink() or any(part in PRIVATE for part in rel.parts):findings.append((str(rel),'private state or symlink'))
        data=path.read_bytes()
        chunks=[]
        if path.suffix.lower()=='.png':
            images+=1;offset=8
            while offset+12<=len(data):
                length=struct.unpack('>I',data[offset:offset+4])[0]
                kind=data[offset+4:offset+8]
                if kind in (b'tEXt',b'iTXt',b'eXIf'):chunks.append(data[offset+8:offset+8+length])
                if kind==b'zTXt':findings.append((str(rel),'compressed metadata requires manual review'))
                offset+=12+length
            data=b'\n'.join(chunks)
        elif path.suffix not in TEXT and not path.name.startswith('.'):continue
        for label,pattern in RULES.items():
            if pattern.search(data):findings.append((str(rel),label))
    for path,label in findings:print(f'REVIEW {path}: {label}')
    print(f'Scanned {count} source files, including metadata in {images} PNG images.')
    print('PASS: no configured findings.' if not findings else f'FAIL: {len(findings)} findings.')
    return bool(findings)

def is_zip(data):
    return b'PK\x05\x06' in data[-65558:]

def walk(name, data, depth=0):
    """Yield (path, bytes) for a blob or, when it is a zip, recursively for its members.
    A readable zip is judged by its members, so a stored (uncompressed) member is not
    reported twice, once inside the container and once on its own."""
    archive = None
    if depth <= 3 and is_zip(data):
        try:
            archive = zipfile.ZipFile(io.BytesIO(data))
        except zipfile.BadZipFile:
            archive = None
    if archive is None:
        yield name, data
        return
    for info in archive.infolist():
        if not info.is_dir():
            yield from walk(name + '!' + info.filename, archive.read(info), depth + 1)

def key_allowed(path, key, web_roots):
    """A public key at one of the two expected places: analytics.config.lua at the root
    of a .love, or a web build's root index.html (the root of a folder given on the
    command line, or the root of a zip). An index.html anywhere deeper is a finding."""
    if not key.startswith(b'gt_pub_'):
        return False
    parts = path.split('!')
    if len(parts) >= 2 and parts[-1] == CONFIG:
        return parts[-2].endswith('.love')
    if len(parts) == 1:
        return path in web_roots
    return len(parts) == 2 and parts[0].endswith('.zip') and parts[1] == 'index.html'

def audit_artifacts(paths):
    findings = []; blobs = 0; keys = 0
    files = []
    web_roots = set()
    for path in paths:
        path = Path(path)
        if path.is_dir():
            files += [p for p in sorted(path.rglob('*')) if p.is_file() and not p.is_symlink()]
            web_roots.add(str(path / 'index.html'))
        elif path.is_file():
            files.append(path)
            if path.name == 'index.html':
                web_roots.add(str(path))
        else:
            findings.append((str(path), 'artifact missing'))
    for path in files:
        source_zip = 'source' in path.name.lower() and path.suffix == '.zip'
        for inner, data in walk(str(path), path.read_bytes()):
            blobs += 1
            if source_zip and inner.split('!')[-1].rsplit('/', 1)[-1] == CONFIG:
                findings.append((inner, 'analytics config in a source zip'))
            for match in KEY.finditer(data):
                keys += 1
                if source_zip:
                    findings.append((inner, 'ingest key in a source zip'))
                elif not key_allowed(inner, match.group(0), web_roots):
                    findings.append((inner, 'ingest key outside the two expected places'))
    for path, label in findings: print(f'REVIEW {path}: {label}')
    print(f'Scanned {len(files)} artifact files ({blobs} files including archive members); '
          f'{keys} ingest key occurrences.')
    print('PASS: no configured findings.' if not findings else f'FAIL: {len(findings)} findings.')
    return bool(findings)

if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--artifact', nargs='+', metavar='PATH', help='scan built artifacts instead of source')
    options = parser.parse_args()
    raise SystemExit(audit_artifacts(options.artifact) if options.artifact else main())
