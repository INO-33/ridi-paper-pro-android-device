#!/usr/bin/env python
"""Remove only replaced PAPER apps from the system image staging tree.

Android O's package overrides do not delete old incremental install outputs.
Run after replacement APK dependencies are installed, before listing/packing.
Compatible with both the Android O Python 2 host and Python 3.
"""
from __future__ import print_function

import argparse
import glob
import os
import shutil
import sys
import zipfile


def replacement_ready(system_dir, name):
    directory = os.path.join(system_dir, 'app', name)
    if os.path.islink(directory):
        raise ValueError('replacement directory must not be a symlink: ' + name)
    apks = glob.glob(os.path.join(directory, '*.apk'))
    if len(apks) != 1 or os.path.islink(apks[0]):
        raise ValueError('expected exactly one replacement APK: ' + name)
    with zipfile.ZipFile(apks[0]) as apk:
        if 'AndroidManifest.xml' not in apk.namelist():
            raise ValueError('incomplete replacement APK: ' + name)
        if name == 'ridi_webview' and 'lib/armeabi-v7a/libwebviewchromium.so' not in apk.namelist():
            raise ValueError('replacement WebView lacks ARM native library')


def prune(system_dir, webview=False, launcher=False):
    system_dir = os.path.abspath(system_dir)
    if os.path.islink(system_dir) or not os.path.isdir(system_dir):
        raise ValueError('system staging directory is missing or is a symlink')
    for parent in ('app', 'priv-app'):
        if os.path.islink(os.path.join(system_dir, parent)):
            raise ValueError('system app parent must not be a symlink')
    names = []
    # Validate every requested replacement before deleting any old package.
    if webview:
        replacement_ready(system_dir, 'ridi_webview')
        names.append('webview')
    if launcher:
        replacement_ready(system_dir, 'RidiPaperLauncher')
        names.extend(('Launcher2', 'Launcher3'))
    removed = []
    for parent in ('app', 'priv-app'):
        for name in names:
            path = os.path.join(system_dir, parent, name)
            if os.path.islink(path):
                os.unlink(path)
            elif os.path.isdir(path):
                shutil.rmtree(path)
            elif os.path.exists(path):
                raise ValueError('unexpected non-directory app path: ' + path)
            else:
                continue
            removed.append(parent + '/' + name)
    return removed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--system-dir', required=True)
    parser.add_argument('--webview', action='store_true')
    parser.add_argument('--launcher', action='store_true')
    args = parser.parse_args()
    try:
        removed = prune(args.system_dir, args.webview, args.launcher)
    except (ValueError, IOError, OSError, zipfile.BadZipfile) as error:
        print('PAPER app pruning failed: ' + str(error), file=sys.stderr)
        return 1
    if removed:
        print('PAPER removed obsolete apps: ' + ', '.join(removed))
    return 0


if __name__ == '__main__':
    sys.exit(main())
