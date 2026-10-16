#!/usr/bin/env python3
"""Write Afterimage's analytics.config.lua for a release build.

The public ingest key reaches a build only through this file, and only from
the RAVENSIGHT_PUBLIC_KEY environment variable at build time. It is never
committed: a clone or a fork has no key, so its builds send nothing.

    RAVENSIGHT_PUBLIC_KEY=gt_pub_... analytics_config.py --distribution native-release

prints the config to stdout. A web build gets a keyless config (--web): the
page holds the key, the game only needs to know it may show the toggle.
"""
import argparse
import os
import re
import sys

NAME = 'analytics.config.lua'
DISTRIBUTIONS = ('native-release', 'web-pages', 'web-itch')
# Only a public key may ship. A gt_live_ key would let anyone with the build
# write as the production game, so it is refused here rather than shipped.
KEY = re.compile(r'^gt_pub_[A-Za-z0-9_-]{16,64}$')
API_URL = re.compile(r'^https?://[A-Za-z0-9.-]+(?::[0-9]{1,5})?(?:/[A-Za-z0-9._/-]*)?$')


def public_key(env=None):
    """The validated key from the environment, or '' when unset."""
    env = os.environ if env is None else env
    key = (env.get('RAVENSIGHT_PUBLIC_KEY') or '').strip()
    if key and not KEY.match(key):
        raise ValueError('RAVENSIGHT_PUBLIC_KEY must be a public key (gt_pub_ followed by 16 to 64 '
                         'letters, digits, - or _); refusing to build with it')
    return key


def api_url(env=None):
    env = os.environ if env is None else env
    url = (env.get('RAVENSIGHT_API_URL') or '').strip()
    if url and not API_URL.match(url):
        raise ValueError('RAVENSIGHT_API_URL is not a plain http(s) URL')
    return url


def render(distribution, key='', url='', web=False):
    """The Lua source of the config. Every value is validated before it is quoted."""
    if distribution not in DISTRIBUTIONS:
        raise ValueError('unknown distribution ' + repr(distribution))
    if key and not KEY.match(key):
        raise ValueError('not a public key')
    if web and key:
        raise ValueError('a web build is keyless: the page holds the key')
    if url and not API_URL.match(url):
        raise ValueError('not a plain http(s) URL')
    lines = ['-- Written by the release tools at build time. Never commit this file.',
             'return {',
             '  distribution = "%s",' % distribution]
    if key:
        lines.append('  ingestKey = "%s",' % key)
    if url:
        lines.append('  apiUrl = "%s",' % url)
    if web:
        lines.append('  web = true,')
    lines.append('}')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--distribution', required=True, choices=DISTRIBUTIONS)
    parser.add_argument('--web', action='store_true', help='keyless config for a love.js build')
    args = parser.parse_args()
    try:
        key = '' if args.web else public_key()
        if not args.web and not key:
            print('RAVENSIGHT_PUBLIC_KEY is not set; no config written', file=sys.stderr)
            return 3
        sys.stdout.write(render(args.distribution, key, api_url(), args.web))
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
