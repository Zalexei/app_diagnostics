#!/usr/bin/env python3
"""Tap Flutter widgets by label over adb (uiautomator dump), for manual e2e runs.

usage: tool/ui.py SERIAL tap LABEL      tap the first node whose text/content-desc starts with LABEL
       tool/ui.py SERIAL labels         print visible labels
"""
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


def dump(serial):
    subprocess.run(['adb', '-s', serial, 'shell', 'uiautomator', 'dump', '/sdcard/ui.xml'],
                   check=True, capture_output=True)
    xml = subprocess.run(['adb', '-s', serial, 'shell', 'cat', '/sdcard/ui.xml'],
                         check=True, capture_output=True, text=True).stdout
    return ET.fromstring(xml[xml.index('<'):])


def labels(root):
    for node in root.iter('node'):
        label = node.get('text') or node.get('content-desc') or ''
        if label.strip():
            yield label, node.get('bounds')


def main():
    serial, cmd = sys.argv[1], sys.argv[2]
    root = dump(serial)
    if cmd == 'labels':
        for label, bounds in labels(root):
            print(bounds, label.replace('\n', ' | ')[:150])
        return
    target = sys.argv[3]
    for label, bounds in labels(root):
        if label.startswith(target):
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', bounds))
            subprocess.run(['adb', '-s', serial, 'shell', 'input', 'tap',
                            str((x1 + x2) // 2), str((y1 + y2) // 2)], check=True)
            print('tapped', label.split('\n')[0], bounds)
            return
    sys.exit(f'not found: {target}')


if __name__ == '__main__':
    main()
