#!/bin/sh

# disk-usage.sh - report when disk space starts getting low

# Credit to:
# http://www.cyberciti.biz/faq/mac-osx-unix-get-an-alert-when-my-disk-is-full/

check() {
	FS=$1
	CURRENT=$(df -P "$FS" | tail -n1 | awk '{print $5}' | sed 's/%//')
	test "$CURRENT" -gt "$threshold" &&
		echo "$FS: file system usage at $CURRENT%" &&
		return 1
	return 0
}

threshold=80
while test $# -gt 0
do
	case "$1" in
	--threshold|-t)
		shift
		threshold=$1
		;;
	*)
		check "$1"
		;;
	esac
	shift
done
