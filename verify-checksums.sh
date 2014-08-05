#!/bin/sh

# verify-checksums.sh - A script to check .md5 and .sha1 checksums.
# Because apparently there is no built-in way to do this en masse?
# And there is no Maven plugin to do it either? Shocking! ;-)

if [ "$1" == "" ]
then
	echo "Usage: verify-checksum.sh [-v] <directory-to-scan> [<another-directory> ...]"
	exit 1
fi

verbose=""

for arg in $@
do
	dir=""
	case "$arg" in
		-v)
			verbose=1
			;;
		*)
			dir="$arg"
			;;
	esac
	echo "dir = $dir"
	test -n "$dir" || continue

	if [ ! -d "$dir" ]
	then
		echo "Warning: skipping invalid directory: $dir"
		continue
	fi

	# verify MD5 checksums
	for md5 in $(find "$dir" -name '*.md5')
	do
		file="${md5%.md5}"
		if [ ! -f "$file" ]
		then
			echo "[FAIL] $file: file does not exist"
			continue
		fi
		expected="$(cat "$md5")"
		actual="$(md5sum "$file" | cut -d ' ' -f 1)"
		if [ "$expected" == "$actual" ]
		then
			test "$verbose" && echo "[PASS] $file"
		else
			echo "[FAIL] $file: expected $expected but was $actual"
		fi
	done

	# verify SHA-1 checksums
	for sha1 in $(find "$dir" -name '*.sha1')
	do
		file="${sha1%.sha1}"
		if [ ! -f "$file" ]
		then
			echo "[FAIL] $file: file does not exist"
			continue
		fi
		expected="$(cat "$sha1")"
		actual="$(sha1sum "$file" | cut -d ' ' -f 1)"
		if [ "$expected" == "$actual" ]
		then
			test "$verbose" && echo "[PASS] $file"
		else
			echo "[FAIL] $file: expected $expected but was $actual"
		fi
	done
done
