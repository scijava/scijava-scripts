#!/bin/env python

import os, subprocess

def extract_classes(f):
    lines = subprocess.check_output(['jar', 'tf', f]).split()
    result = set()
    for line in lines:
        v = line.decode('utf-8').strip()
        if v.endswith('.class'):
            result.add(v)
    return result

print('Reading JAR files... ', end='', flush=True)
paths = []
for root, dirs, files in os.walk("."):
   for name in files:
       if not name.lower().endswith('.jar'): continue
       paths.append(os.path.join(root, name))

classes = {}
count = 0
perc = ''
for path in paths:
    count += 1
    classes[path] = extract_classes(path)
    print('\b' * len(perc), end='')
    perc = str(round(100 * count / len(paths))) + '%    '
    print(perc, end='', flush=True)

exceptions = ['module-info.class']
print('Scanning for duplicate classes..')
for jar1 in classes:
    for jar2 in classes:
        if jar1 == jar2: continue
        dups = classes[jar1].intersection(classes[jar2])
        for exc in exceptions:
            if exc in dups: dups.remove(exc)
        if len(dups) > 0:
            print(f'==> {jar1} and {jar2} have duplicates! E.g. {next(iter(dups))}')

print('Done!')
