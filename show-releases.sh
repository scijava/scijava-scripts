#!/bin/sh

die () {
	echo "$*" >&2
	exit 1
}

check () {
	(cd "$1" && check-release.pl)
}

while [ $# -gt 0 ]
do
	if [ -d "$1" ]
	then
		check "$1"
	else
		echo "Invalid directory: $1"
	fi
	shift
done
