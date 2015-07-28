#!/bin/sh

# ============================================================================
# melting-pot.sh
# ============================================================================
# Tests all components of a project affected by changes in its dependencies.
#
# First, an anecdote illustrating the problem this script solves:
#
# Suppose you have a large application, org:app:1.0.0, with many dependencies:
# org:foo:1.2.3, org:bar:3.4.5, and many others.
#
# Now suppose you make some changes to foo, and want to know whether deploying
# them (i.e., releasing a new foo and updating app to depend on that release)
# will break the app. So you manually update your local copy of app to depend
# on org:foo:1.3.0-SNAPSHOT, and run the build (including tests, of course).
#
# The build passes, but this alone is insufficient: org:bar:3.4.5 also depends
# on org:foo:1.2.3, so you manually update bar to use org:foo:1.3.0-SNAPSHOT,
# then build bar to verify that it also is not broken by the update.
#
# This process quickly becomes very tedious when there are dozens of
# components of app which all depend on foo.
#
# And more importantly, testing each component individually in this manner is
# still insufficient to determine whether all of them will truly work together
# at runtime, where only a single version of each component is deployed.
#
# For example: suppose org:bar:3.4.5 depends on org:lib:8.0.0, while
# org:foo:1.2.3 depends on org:lib:7.0.0. The relevant facts are:
#
# * Your new foo (org:foo:1.3.0-SNAPSHOT) builds against lib 7, and portions
#   of it rely on lib-7-specific API.
#
# * The bar component pinned to foo 1.3.0-SNAPSHOT builds against lib 8; it
#   compiles with passing tests because bar only invokes portions of the foo
#   API which do not require lib-7-specific API.
#
# In this scenario, it is lib 8 that is actually deployed at runtime with the
# app, so parts of foo will be broken, even though both foo and bar build with
# passing tests individually.
#
# This "melting pot" build seeks to overcome many of these issues by unifying
# all components of the app into a single multi-module build, with all
# versions uniformly pinned to the ones that will actually be deployed at
# runtime.
#
# This goal is achieved by synthesizing a multi-module build including all
# affected components (or optionally, all components period) of the specific
# project, and then executing a Maven build with uniformly overridden versions
# of all components to the ones resolved for the project itself.
#
# IMPORTANT IMPLEMENTATION DETAIL! The override works by setting a version
# property for each component of the form "artifactId.version"; it is assumed
# that all components declare their dependencies using version properties of
# this form. E.g.:
#
#   <dependency>
#     <groupId>com.google.guava</groupId>
#     <artifactId>guava</artifactId>
#     <version>${guava.version}</version>
#   </dependency>
#
# Using dependencyManagement is fine too, as long as it then uses this pattern
# to declare the versions as properties, which can be overridden.
#
# Any dependency which does not declare a version property matching this
# assumption will not be properly overridden in the melting pot!
#
# Author: Curtis Rueden
# Dependencies: git, mvn, xmllint
# ============================================================================

# -- Functions --

stderr() {
	>&2 echo "$@"
}

debug() {
	test "$verbose" &&
		stderr "[DEBUG] $@"
}

error() {
	stderr "[ERROR] $@"
}

die() {
	code="$1"
	shift
	error $@
	exit "$code"
}

unknownArg() {
	error "Unknown option: $@"
	usage=1
}

parseArguments() {
	while [ $# -ge 1 ]
	do
		case "$1" in
			-c|--changes)
				changes="$2"
				shift
				;;
			-i|--includes)
				includes="$2"
				shift
				;;
			-e|--excludes)
				excludes="$2"
				shift
				;;
			-r|--remoteRepos)
				remoteRepos="$2"
				shift
				;;
			-l|--localRepo)
				repoBase="$2"
				shift
				;;
			-o|--outputDir)
				outputDir="$2"
				shift
				;;
			-v|--verbose)
				verbose=1
				;;
			-f|--force)
				force=1
				;;
			-h|--help)
				usage=1
				;;
			-*)
				unknownArg "$1"
				;;
			*)
				test -z "$project" && project="$1" ||
					unknownArg "$1"
				;;
		esac
		shift
	done

	test -z "$project" && error "No project specified!" && usage=1

	if [ "$usage" ]
	then
		echo "Usage: $(basename "$0") <project> [-c <GAVs>] \\
       [-i <GAs>] [-e <GAs>] [-r <URLs>] [-l <dir>] [-o <dir>] [-vfh]

<project>
    The project to build, including dependencies, with consistent versions.
-c, --changes
    Comma-separated list of GAVs to inject into the project, replacing
    normal versions. E.g.: \"com.mycompany:myartifact:1.2.3-SNAPSHOT\"
-i, --includes
    Comma-separated list of GAs (no version; wildcards OK for G or A) to
    include in the build. All by default. E.g.: \"mystuff:*,myotherstuff:*\"
-e, --excludes
    Comma-separated list of GAs (no version; wildcards OK for G or A) to
    exclude from the build. E.g.: \"mystuff:extraneous,mystuff:irrelevant\"
-r, --remoteRepos
    Comma-separated list of additional remote Maven repositories to check
    for artifacts, in the format id::[layout]::url or just url.
-l, --localRepos
    Overrides the directory of the Maven local repository cache.
-o, --outputDir
    Overrides the output directory. The default is \"melting-pot\".
-v, --verbose
    Enable verbose/debugging output.
-f, --force
    Wipe out the output directory if it already exists.
-h, --help
    Display this usage information."
		exit 1
	fi

	# Assign default parameter values.
	test "$outputDir" || outputDir="melting-pot"
	test "$repoBase" || repoBase="$HOME/.m2/repository"
}

createDir() {
	test -z "$force" -a -e "$1" &&
		die 2 "Directory already exists: $1"

	rm -rf "$1"
	mkdir -p "$1"
	cd "$1"
}

groupId() {
	echo "${1%%:*}"
}

artifactId() {
	result="${1#*:}" # strip groupId
	echo "${result%%:*}"
}

version() {
	result="${1#*:}" # strip groupId
	case "$result" in
		*:*)
			result="${result#*:}" # strip artifactId
			case "$result" in
				*:*:*:*)
					# G:A:P:C:V:S
					result="${result#*:}" # strip packaging
					result="${result#*:}" # strip classifier
					;;
				*:*:*)
					# G:A:P:V:S
					result="${result#*:}" # strip packaging
					;;
				*)
					# G:A:V or G:A:V:?
					;;
			esac
			echo "${result%%:*}"
			;;
	esac
}

# Converts the given GAV into a path in the local repository cache.
repoPath() {
	gPath="$(echo "$(groupId "$1")" | tr :. /)"
	aPath="$(artifactId "$1")"
	vPath="$(version "$1")"
	echo "$repoBase/$gPath/$aPath/$vPath"
}

# Gets the path to the given GAV's POM file in the local repository cache.
pomPath() {
	pomFile="$(artifactId "$1")-$(version "$1").pom"
	echo "$(repoPath "$1")/$pomFile"
}

# Fetches the POM for the given GAV into the local repository cache.
downloadPOM() {
	mvn dependency:get \
		-DrepoUrl="$remoteRepos" \
		-DgroupId="$(groupId "$1")" \
		-DartifactId="$(artifactId "$1")" \
		-Dversion="$(version "$1")" \
		-Dpackaging=pom
}

# Gets the POM path for the given GAV, ensuring it exists locally.
pom() {
	pomPath="$(pomPath "$1")"
	test -f "$pomPath" || downloadPOM "$1"
	echo "$pomPath"
}

# Gets the SCM URL for the given GAV.
scmURL() {
	scmXPath="//*[local-name()='project']/*[local-name()='scm']/*[local-name()='connection']"
	xmllint --xpath "$scmXPath" "$(pom "$1")" | sed -E 's/.*>scm:git:(.*)<.*/\1/'
}

# Gets the SCM tag for the given GAV.
scmTag() {
	echo "$(artifactId "$1")-$(version "$1")"
}

# Fetches the source code for the given GAV. Returns the directory.
retrieveSource() {
	scmURL="$(scmURL "$1")"
	scmTag="$(scmTag "$1")"
	dir="$(groupId "$1")/$(artifactId "$1")"
	git clone "$scmURL" --branch "$scmTag" --depth 1 "$dir" 2> /dev/null
	echo "$dir"
}

# Gets the list of dependencies for the project in the CWD.
deps() {
	mvn dependency:list | grep '^\[INFO\]    [^ ]' | sed 's/\[INFO\]    //'
}

# Checks whether the given GA(V) matches the specified filter pattern.
gaMatch() {
	ga="$1"
	filter="$2"
	g="$(groupId "$ga")"
	a="$(artifactId "$ga")"
	fg="$(groupId "$filter")"
	fa="$(artifactId "$filter")"
	test "$fg" = "$g" -o "$fg" = "*" || return
	test "$fa" = "$a" -o "$fa" = "*" || return
	echo 1
}

# Determines whether the given GA(V) version is being overridden.
isChanged() {
	local IFS=","

	for change in $changes
	do
		test "$(gaMatch "$1" "$change")" && echo 1 && return
	done
}

# Determines whether the given GA(V) meets the inclusion criteria.
isIncluded() {
	# do not include the changed artifacts we are testing against
	test "$(isChanged "$1")" && return

	local IFS=","

	# ensure GA is not excluded
	for exclude in $excludes
	do
		test "$(gaMatch "$1" "$exclude")" && return
	done

	# ensure GA is included
	test -z "$includes" && echo 1 && return
	for include in $includes
	do
		test "$(gaMatch "$1" "$include")" && echo 1 && return
	done
}

# Generates an aggregator POM for all modules in the current directory.
generatePOM() {
	echo '<?xml version="1.0" encoding="UTF-8"?>' > pom.xml
	echo '<project xmlns="http://maven.apache.org/POM/4.0.0"' >> pom.xml
	echo '	xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"' >> pom.xml
	echo '	xsi:schemaLocation="http://maven.apache.org/POM/4.0.0' >> pom.xml
	echo '		http://maven.apache.org/xsd/maven-4.0.0.xsd">' >> pom.xml
	echo '	<modelVersion>4.0.0</modelVersion>' >> pom.xml
	echo >> pom.xml
	echo '	<groupId>melting-pot</groupId>' >> pom.xml
	echo '	<artifactId>melting-pot</artifactId>' >> pom.xml
	echo '	<version>0.0.0-SNAPSHOT</version>' >> pom.xml
	echo '	<packaging>pom</packaging>' >> pom.xml
	echo >> pom.xml
	echo '	<name>Melting Pot</name>' >> pom.xml
	echo >> pom.xml
	echo '	<modules>' >> pom.xml
	for dir in */*
	do
		test -d "$dir" &&
			echo "		<module>$dir</module>" >> pom.xml
	done
	echo '	</modules>' >> pom.xml
	echo '</project>' >> pom.xml
}

# Creates and tests an appropriate multi-module reactor for the given project.
# All relevant dependencies which match the inclusion criteria are linked into
# the multi-module build, with each changed GAV overridding the originally
# specified version for the corresponding GA.
meltDown() {
	# Fetch the project source code.
	debug "$1: fetching project source"
	dir="$(retrieveSource "$1")"

	# Get the project dependencies.
	debug "$1: determining project dependencies"
	cd "$dir"
	deps="$(deps)"
	cd - > /dev/null

	args="-Denforcer.skip"

	# Process the dependencies.
	debug "$1: processing project dependencies"
	for dep in $deps
	do
		g="$(groupId "$dep")"
		a="$(artifactId "$dep")"
		v="$(version "$dep")"
		gav="$g:$a:$v"

		test -z "$(isChanged "$gav")" &&
			args="$args -D$a.version=$v"

		if [ "$(isIncluded "$gav")" ]
		then
			debug "$1: $a: fetching component source"
			dir="$(retrieveSource "$gav")"
		fi
	done

	# Override versions of changed GAVs.
	debug "$1: processing changed components"
	local TLS=,
	for gav in $changes
	do
		a="$(artifactId "$gav")"
		v="$(version "$gav")"
		args="$args -D$a.version=$v"
	done
	unset TLS

	# Generate the aggregator POM.
	debug "Generating aggregator POM"
	generatePOM

	# Build everything.
	debug "Building the project!"
	# NB: All code is fresh; no need to clean.
	mvn $args test

	debug "$1: complete"
}

# -- Main --

parseArguments $@
createDir "$outputDir"
meltDown "$project"
