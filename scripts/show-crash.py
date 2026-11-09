#!/usr/bin/env python3
"""Prints what crashed, from a macOS crash report (.ips): the exception, the reason AppKit or
Swift gave, and the crashed thread's frames. CI runs it when a test crashes, because a crashed
test leaves no "failed" line in xcodebuild's log."""
import json
import sys

for path in sys.argv[1:]:
    print(f'== {path}')
    try:
        text = open(path, encoding='utf-8', errors='replace').read()
        header, _, body = text.partition('\n')
        report = json.loads(body) if body.strip() else json.loads(header)
    except Exception as error:  # not JSON: an older .crash file; show its top
        print(f'(not an .ips report: {error})')
        print('\n'.join(text.splitlines()[:60]))
        continue
    print('exception:', report.get('exception'))
    print('termination:', report.get('termination', {}).get('indicator'))
    for key in ('asi', 'ktriageinfo'):
        if report.get(key):
            print(f'{key}:', report[key])
    images = [image.get('name', '?') for image in report.get('usedImages', [])]

    def show(frames, title):
        print(title)
        for frame in frames[:40]:
            image = images[frame['imageIndex']] if frame.get('imageIndex', -1) < len(images) else '?'
            where = f" {frame.get('sourceFile')}:{frame.get('sourceLine')}" if frame.get('sourceFile') else ''
            print(f"  {image}  {frame.get('symbol', '?')}{where}")

    if report.get('lastExceptionBacktrace'):
        show(report['lastExceptionBacktrace'], 'last exception backtrace:')
    threads = report.get('threads', [])
    crashed = report.get('faultingThread', 0)
    if crashed < len(threads):
        show(threads[crashed].get('frames', []), f'crashed thread {crashed}:')
