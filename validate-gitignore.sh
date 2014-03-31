#!/bin/sh

# This script can be used to identify unnecessary entries in the .gitignore
# file.
#
# Three modes are available:
#
# --validate
#	prints out unnecessary entries
# --clean
#	prints out the contents of .gitignore, skipping unnecessary entries
# --fix
#	overwrites .gitignore with the output of --clean

die () {
	echo "$*" >&2
	exit 1
}

while test $# -gt 0
do
	case "$1" in
	--fix|--validate|--clean) mode=${1#--};;
	*) die "Unknown command: $1";;
	esac
	shift
done

test -f .gitignore ||
die "No .gitignore file?"

handle_line () {
	case "$1" in
	''|\#*)
		printf '%s\n' "$1"
		continue
		;;
	/*)
		if eval ls -d ."$1" > /dev/null 2>&1
		then
			printf "%s\n" "$1"
		elif test "validate" = "$mode"
		then
			echo "Unnecessary: $1" 1>&2
		fi
		;;
	esac
}

cleaned="$(cat .gitignore |
	while read line 
	do
		handle_line "$line"
	done)"

case "$mode" in
fix)
	printf "%s" "$cleaned" > .gitignore
	;;
clean)
	printf "%s" "$cleaned"
	;;
esac
