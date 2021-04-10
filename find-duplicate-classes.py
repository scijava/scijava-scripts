#!/bin/env python

import os, subprocess

def extract_classes(f):
    lines = subprocess.check_output(['jar', 'tf', f]).split()
    result = set()
    for line in lines:
        v = line.decode('utf-8').strip()
        if v.endswith('.class') and not v.endswith('module-info.class'):
            result.add(v)
    return result

print('Reading JAR files... ', end='', flush=True)
paths = []
for root, dirs, files in os.walk('.'):
   for name in files:
       if not name.lower().endswith('.jar'): continue
       paths.append(os.path.join(root, name))
paths.sort()

classes = {}
count = 0
perc = ''
for path in paths:
    count += 1
    classes[path] = extract_classes(path)
    print('\b' * len(perc), end='')
    perc = str(round(100 * count / len(paths))) + '% '
    print(perc, end='', flush=True)

print()
print('Scanning for duplicate classes...')
for i1 in range(len(paths)):
    p1 = paths[i1]
    duplist = []
    for i2 in range(i1 + 1, len(paths)):
        p2 = paths[i2]
        dups = classes[p1].intersection(classes[p2])
        if len(dups) > 0:
            duplist.append(f'==> {p2} (e.g. {next(iter(dups))})')
    if len(duplist) > 0:
        print(p1)
        for line in duplist:
            print(line)

print('Done!')
