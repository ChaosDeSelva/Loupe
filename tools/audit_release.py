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
import stat
from pathlib import PurePosixPath
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

MAX_DEPTH = 8
MAX_EXPANDED_BYTES = 512 * 1024 * 1024
MAX_MEMBERS = 10000

class AuditError(ValueError):
    pass

def walk(name, data, depth=0, budget=None):
    """Fail closed on unscannable archives; never extract archive members."""
    budget = budget if budget is not None else [0, 0]
    expected_archive = name.lower().endswith(('.zip', '.love')) or is_zip(data) or data.startswith(b'PK\x03\x04')
    if not expected_archive:
        yield name, data
        return
    if depth >= MAX_DEPTH:
        raise AuditError('archive nesting exceeds scan limit')
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for info in archive.infolist():
                member = PurePosixPath(info.filename.replace('\\', '/'))
                if not member.parts or member.is_absolute() or '..' in member.parts or ':' in member.parts[0]:
                    raise AuditError('unsafe archive member path')
                if stat.S_ISLNK(info.external_attr >> 16):
                    raise AuditError('symlink in archive')
                if info.flag_bits & 1:
                    raise AuditError('encrypted archive cannot be scanned')
                if info.is_dir(): continue
                budget[0] += info.file_size
                budget[1] += 1
                if budget[0] > MAX_EXPANDED_BYTES or budget[1] > MAX_MEMBERS:
                    raise AuditError('archive expansion exceeds scan limit')
                yield from walk(name + '!' + info.filename, archive.read(info), depth + 1, budget)
    except (zipfile.BadZipFile, RuntimeError, NotImplementedError, OSError) as error:
        raise AuditError('unreadable archive: ' + type(error).__name__) from error

def source_member(path):
    return any('source' in part.lower() and part.lower().endswith('.zip') for part in path.split('!'))

def key_allowed(path, key, web_roots):
    if not key.startswith(b'gt_pub_') or source_member(path): return False
    parts = path.split('!')
    if len(parts) >= 2 and parts[-1] == CONFIG:
        return parts[-2].endswith('.love')
    if len(parts) == 1: return path in web_roots
    return len(parts) == 2 and parts[0].endswith('.zip') and parts[1] == 'index.html'

def public_key_slots(path, data):
    # Only the injected assignment may contain a public key, not arbitrary
    # comments, URLs or copied credentials elsewhere in an allowlisted file.
    name = path.split('!')[-1]
    pattern = (rb"\bingestKey\s*=\s*[\"'](gt_pub_[A-Za-z0-9_-]{16,64})[\"']"
               if name == CONFIG else
               rb"\bconst\s+RAVENSIGHT_PUBLIC_KEY\s*=\s*[\"'](gt_pub_[A-Za-z0-9_-]{16,64})[\"']")
    return {m.span(1) for m in re.finditer(pattern, data)}

def private_path(name):
    for segment in name.split('!'):
        for part in PurePosixPath(segment.replace('\\', '/')).parts:
            if part in PRIVATE or part in {'.git', '.aws', '.ssh'} or part.startswith('.env.'):
                return True
    return False

def audit_artifacts(paths):
    findings = []; blobs = 0; keys = 0; files = []; web_roots = set()
    for raw in paths:
        path = Path(raw)
        if path.is_symlink():
            findings.append((str(path), 'symlink artifact')); continue
        if path.is_dir():
            for p in sorted(path.rglob('*')):
                if p.is_symlink(): findings.append((str(p), 'symlink artifact'))
                elif p.is_file(): files.append(p)
            web_roots.add(str(path / 'index.html'))
        elif path.is_file():
            files.append(path)
            if path.name == 'index.html': web_roots.add(str(path))
        else: findings.append((str(path), 'artifact missing'))
    for path in files:
        try:
            for inner, data in walk(str(path), path.read_bytes()):
                blobs += 1
                if private_path(inner): findings.append((inner, 'private state in artifact'))
                if source_member(inner) and inner.split('!')[-1].rsplit('/', 1)[-1] == CONFIG:
                    findings.append((inner, 'analytics config in a source zip'))
                # Apply the same credential/path/branding rules to artifacts as
                # source; previously this mode checked only Ravensight keys.
                for label, pattern in RULES.items():
                    if label != 'Ravensight ingest key' and pattern.search(data):
                        findings.append((inner, label))
                slots = public_key_slots(inner, data)
                matches = list(KEY.finditer(data))
                for match in matches:
                    keys += 1
                    if not key_allowed(inner, match.group(0), web_roots) or match.span() not in slots or len(matches) != 1:
                        findings.append((inner, 'ingest key outside its single injected public-key assignment'))
        except (AuditError, OSError, ValueError) as error:
            findings.append((str(path), 'scan incomplete: ' + str(error)))
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
