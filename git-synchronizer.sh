#!/bin/sh

# This script wants to synchronize multiple public Git repositories with each
# other
#
# Use it (e.g. in a Jenkins job) like this:
#
#	$0 <Git-URL>...
#
# where Git-URL is either a push URL, or a pair of a fetch and a push URL
# separated by an equal sign.
#
# Example:
#
# git-synchronizer.sh \
#	git://fiji.sc/imglib.git=fiji.sc:/srv/git/imglib.git \
#	git://github.com/imglib/imglib=github.com:imglib/imglib

errors=
add_error () {
	errors="$(printf "%s\n\n%s\n\n" "$errors" "$*")"
}

url2remotename () {
	echo "${1%=*}" |
	sed 's/[^-A-Za-z0-9._]/_/g'
}

nullsha1=0000000000000000000000000000000000000000
find_deleted () {
	test -n "$2" || return
	printf '%s\n%s\n%s\n' "$1" "$2" "$2" |
	sort -k 3 |
	uniq -u -f 2 |
	sed "s/^.\{40\}/$nullsha1/"
}

find_modified () {
	printf '%s\n%s\n' "$2" "$1" |
	sort -s -k 3 |
	uniq -u |
	uniq -d -f 2 |
	uniq -f 2
}

find_new () {
	printf '%s\n%s\n%s\n' "$1" "$1" "$2" |
	sort -k 3 |
	uniq -u -f 2
}

get_remote_branches () {
	name="$1"

	git for-each-ref refs/remotes/$name/\* |
	sed "s|	refs/remotes/$name/|	|"
}

fetch_from () {
	url="${1%=*}"
	pushurl="${1#*=}"
	name="$(url2remotename "$url")"

	if test "$url" != "$(git config remote.$name.url 2> /dev/null)"
	then
		git remote add $name $url >&2 || {
			add_error "Could not add remote $name ($url)"
			return 1
		}
	fi
	test -n "$pushurl" &&
	test "$pushurl" != "$url" &&
	git config remote.$name.pushURL "$pushurl"
	previous="$(get_remote_branches $name)"
	git fetch --prune $name >&2 || {
		add_error "Could not fetch $name"
		return 1
	}
	current="$(get_remote_branches $name)"

	find_deleted "$previous" "$current"

	# force modified branches
	find_modified "$previous" "$current" |
	sed 's/^/+/'

	find_new "$previous" "$current"
}

has_spaces () {
	test $# -gt 1
}

get_common_fast_forward () {
	test $# -le 1 && {
		echo "$*"
		return
	}
	head=
	while test $# -gt 0
	do
		commit=$1
		shift
		test -z "$(eval git rev-list --no-walk ^$commit $head $*)" && {
			echo $commit
			return
		}
		head="$head $commit"
	done
	echo $head
}

# Parameter check

test $# -lt 2 && {
	echo "Usage: $0 <Git-URL>[=<push-URL>] <Git-URL>[=<push-URL>]..." >&2
	exit 1
}

test -d .git ||
git init ||
exit

# Fetch

todo=
for urlpair
do
	url="${urlpair%=*}"
	has_spaces $url && {
		add_error "Error: Ignoring URL with spaces: $url"
		continue
	}

	echo "Getting updates from $url..."
	thistodo="$(fetch_from $urlpair)" || {
		add_error "$thistodo"
		continue
	}
	test -z "$thistodo" && continue
	printf "Updates from $url:\n%s\n" "$thistodo"
	todo="$(printf "%s\n%s\n" "$todo" "$thistodo")"
done

remote_branches="$(for url
do
	url="${url%=*}"
	has_spaces $url && continue
	name=$(url2remotename $url)
	git for-each-ref refs/remotes/$name/\* |
	sed "s|^\(.*\)	refs/remotes/\($name\)/|\2 \1 |"
done)"

for ref in $(echo "$remote_branches" |
	sed 's/.* //' |
	sort |
	uniq)
do
	echo "$todo" | grep "	$ref$" > /dev/null 2>&1 && continue
	quoted_ref="$(echo "$ref" | sed 's/\./\\&/g')"
	sha1="$(echo "$remote_branches" |
		sed -n "s|^[^ ]* \([^ ]*\) [^ ]* $quoted_ref$|\1|p" |
		sort |
		uniq)"
	sha1=$(eval get_common_fast_forward $sha1)
	case "$sha1" in
	*\ *)
		add_error "$(printf "Ref $ref is diverging:\n%s\n\n" "$(echo "$remote_branches" |
			grep " $ref$")")"
		continue
		;;
	*)

		if test $# = $(echo "$remote_branches" |
			grep  "$sha1 [^ ]* $ref$" |
			wc -l)
		then
			# all refs agree on one sha1
			continue
		fi
		;;
	esac
	echo "Need to fast-forward $ref to $sha1"
	todo="$(printf "%s\n%s\n" "$todo" "$sha1 commit $ref")"
done

# Verify

# normalize todo

todo="$(echo "$todo" |
	sort -k 3 |
	uniq |
	grep -v '^$')"

# test for disagreeing updates

refs=$(echo "$todo" |
	sed 's/^[^ ]* [^ ]*	//' |
	sort |
	uniq -d)
for ref in $refs
do
	sha1=$(echo "$todo" |
		sed -n "s|^\([^ ]*\) [^ ]*	$ref$|\1|p")
	sha1=$(get_common_fast_forward $sha1)
	has_spaces $sha1 ||
	todo="$(echo "$todo" |
		sed "s|^[^ ]* \([^ ]*	$ref\)$|$sha1 \1|" |
		uniq)"
done

disagreeing=$(echo "$todo" |
	cut -f 2 |
	sort |
	uniq -d)

if test -n "$disagreeing"
then
	message="$(for name in $disagreeing
		do
			echo "$todo" | grep "	$name$"
		done)"
	add_error "$(printf "Incompatible updates:\n%s\n\n" "$message")"
fi

test -z "$todo" || git gc --auto

# make it easier to test whether a name is in $disagreeing via:
# test "$disagreeing" != "${disagreeing#* $name }"
disagreeing=" $disagreeing "

# Push

test -z "$todo" ||
for url
do
	url="${url%=*}"
	has_spaces $url && continue
	name="$(url2remotename $url)"
	pushopts=$(echo "$todo" |
		while read sha1 type ref
		do
			test -z "$sha1" && continue
			test "$disagreeing" = "${disagreeing#* $name }" || continue
			remoteref=refs/remotes/$name/$ref
			if test $sha1 = $nullsha1
			then
				# to delete
				if git rev-parse $remoteref > /dev/null 2>&1
				then
					echo ":refs/heads/$ref"
				fi
			else
				sha1=${sha1#+}
				if test $sha1 != "$(git rev-parse $remoteref 2> /dev/null)"
				then
					if test -n "$(git rev-list "$sha1..$remoteref")"
					then
						# really need to force
						echo "+$sha1:refs/heads/$ref"
					else
						echo "$sha1:refs/heads/$ref"
					fi
				fi
			fi
		done)
	test -z "$pushopts" && continue
	deletefirst=
	case "$(git config "remote.$name.pushurl"; git config "remote.$name.url")" in
	git://*)
		case "$pushopts" in
		*+*)
			add_error "Diverging $url: ${pushopts#*+}"
			;;
		esac
		continue
		;;
	*.sf.net*|*.sourceforge.net*)
		for opt in $pushopts
		do
			test "$opt" = "${opt#+*:}" ||
			deletefirst="$deletefirst :${opt#+*:}"
		done
	esac
	test -z "$deletefirst" ||
	git push $name $deletefirst ||
	add_error "Could not push $deletefirst to $url"
	git push $name $pushopts ||
	add_error "Could not push to $url"
done

# Maybe error out

test -z "$errors" || {
	printf "\n\nErrors:\n%s\n" "$errors" >&2
	exit 1
}
