#!/usr/bin/env python3
"""Scan release source for private files, obvious credentials, local paths, and PNG metadata.
This is a focused preflight, not a guarantee against every secret or a legal review.
"""
import re
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT = {'.lua','.py','.md','.txt','.html','.css','.js','.json','.yml','.yaml','.toml','.sh','.rockspec'}
RULES = {
    'private key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'GitHub token': re.compile(rb'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}'),
    'API secret': re.compile(rb'\bsk-(?:proj-)?[A-Za-z0-9_-]{35,}'),
    'AWS access key': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'personal machine path': re.compile(rb'/Users/[A-Za-z0-9._-]+/|C:\\Users\\[^\\]+\\'),
    'removed branding': re.compile(('first'+'mate|stack'+'hawk').encode(),re.I),
}
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

if __name__=='__main__':raise SystemExit(main())
