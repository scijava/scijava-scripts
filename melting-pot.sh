#!/bin/sh

# ============================================================================
# melting-pot.sh
# ============================================================================
# Tests all components of a project affected by changes in its dependencies.
#
# In particular, this script detects problems caused by diamond dependency
# structures:
#
#   https://jlbp.dev/what-is-a-diamond-dependency-conflict
#
# This "melting pot" build rebuilds every dependency of a project, but at
# unified dependency versions matching those of the toplevel project.
#
# For example, net.imagej:imagej:2.5.0 depends on many components including
# org.scijava:scijava-common:2.88.1 and net.imagej:imagej-ops:0.46.1,
# both of which depend on org.scijava:parsington. But:
#
# - org.scijava:scijava-common:2.88.1 depends on org.scijava:parsington:3.0.0
# - net.imagej:imagej-ops:0.46.1 depends on org.scijava:parsington:2.0.0
#
# ImageJ2 can only depend on one of these versions at runtime. The newer one,
# ideally. SciJava projects use the pom-scijava parent POM as a Bill of
# Materials (BOM) to declare these winning versions, which works great...
# EXCEPT for when newer versions break backwards compatibility, as happened
# here: it's a SemVer-versioned project at different major version numbers.
#
# Enter this melting-pot script. It rebuilds each project dependency from
# source and runs the unit tests, but with all dependency versions pinned to
# match those of the toplevel project.
#
# So in the example above, this script:
#
# 1. gathers the dependencies of net.imagej:imagej:2.5.0;
# 2. clones each dependency from SCM at the correct release tag;
# 3. rebuilds each dependency, but with dependency versions overridden to
#    those of net.imagej:imagej:2.5.0 rather than those originally used for
#    that dependency at that release.
#
# So e.g. in the above scenario, net.imagej:imagej-ops:0.46.1 will be rebuilt
# against org.scijava:parsington:3.0.0, and we will discover whether any of
# parsington's breaking API changes from 2.0.0 to 3.0.0 actually impact the
# compilation or (tested) runtime behavior of imagej-ops.
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
# ============================================================================

# -- Constants --

meltingPotCache="$HOME/.cache/scijava/melting-pot"

# -- Functions --

stderr() { >&2 echo "$@"; }
debug() { test "$debug" && stderr "+ $@"; }
info() { test "$verbose" && stderr "[INFO] $@"; }
warn() { stderr "[WARNING] $@"; }
error() { stderr "[ERROR] $@"; }
die() { error $1; exit $2; }
unknownArg() { error "Unknown option: $@"; usage=1; }

checkPrereqs() {
  while [ $# -gt 0 ]
  do
    which $1 > /dev/null 2> /dev/null
    test $? -ne 0 && die "Missing prerequisite: $1" 255
    shift
  done
}

verifyPrereqs() {
  checkPrereqs git mvn xmllint
  git --version | grep -q 'git version 2' ||
    die "Please use git v2.x; older versions (<=1.7.9.5 at least) mishandle 'git clone <tag> --depth 1'" 254
}

parseArguments() {
  while [ $# -gt 0 ]
  do
    case "$1" in
      -b|--branch)
        branch="$2"
        shift
        ;;
      -c|--changes)
        test "$changes" && changes="$changes,$2" || changes="$2"
        shift
        ;;
      -i|--includes)
        test "$includes" && includes="$includes,$2" || includes="$2"
        shift
        ;;
      -e|--excludes)
        test "$excludes" && excludes="$excludes,$2" || excludes="$2"
        shift
        ;;
      -r|--remoteRepos)
        test "$remoteRepos" && remoteRepos="$remoteRepos,$2" || remoteRepos="$2"
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
      -p|--prune)
        prune=1
        ;;
      -v|--verbose)
        verbose=1
        ;;
      -d|--debug)
        debug=1
        ;;
      -f|--force)
        force=1
        ;;
      -s|--skipBuild)
        skipBuild=1
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

  test -z "$project" -a -z "$usage" &&
    error "No project specified!" && usage=1

  if [ "$usage" ]
  then
    echo "Usage: $(basename "$0") <project> [-b <branch>] [-c <GAVs>] \\
       [-i <GAs>] [-e <GAs>] [-r <URLs>] [-l <dir>] [-o <dir>] [-pvfsh]

<project>
    The project to build, including dependencies, with consistent versions.
    Can be either G:A:V form, or a local directory pointing at a project.
-b, --branch
    Override the branch/tag of the project to build. By default,
    the branch used will be the tag named \"artifactId-version\".
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
-p, --prune
    Build only the components which themselves depend on a changed
    artifact. This will make the build much faster, at the expense of
    not fully testing runtime compatibility across all components.
-v, --verbose
    Enable verbose/debugging output.
-f, --force
    Wipe out the output directory if it already exists.
-s, --skipBuild
    Skips the final build step. Useful for automated testing.
-h, --help
    Display this usage information.

--== Example ==--

    sh melting-pot.sh net.imagej:imagej-common:0.15.1 \\
        -r https://maven.scijava.org/content/groups/public \\
        -c org.scijava:scijava-common:2.44.2 \\
        -i 'org.scijava:*,net.imagej:*,net.imglib2:*,io.scif:*' \\
        -e net.imglib2:imglib2-roi \\
        -v -f -s

This command tests net.imagej:imagej-common:0.15.1 along with all of its
dependencies, pulled from its usual SciJava Maven repository location.

The -c flag is used to override the org.scijava:scijava-common
dependency to use version 2.44.2 instead of its declared version 2.42.0.

Note that such overrides do not need to be release versions; you can
also test SNAPSHOTs the same way.

The -i option is used to include all imagej-common dependencies with
groupIds org.scijava, net.imagej, net.imglib2 and io.scif in the pot.

The -e flag is used to exclude net.imglib2:imglib2-roi from the pot.
"
    exit 1
  fi

  # If project is a local directory path, get its absolute path.
  test -d "$project" && project=$(cd "$project" && pwd)

  # Assign default parameter values.
  test "$outputDir" || outputDir="melting-pot"
  test "$repoBase" || repoBase="$HOME/.m2/repository"
}

createDir() {
  test -z "$force" -a -e "$1" &&
    die "Directory already exists: $1" 2

  rm -rf "$1"
  mkdir -p "$1"
  cd "$1"
}

groupId() {
  echo "${1%%:*}"
}

artifactId() {
  local result="${1#*:}" # strip groupId
  echo "${result%%:*}"
}

version() {
  local result="${1#*:}" # strip groupId
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

classifier() {
  local result="${1#*:}" # strip groupId
  case "$result" in
    *:*)
      result="${result#*:}" # strip artifactId
      case "$result" in
        *:*:*:*)
          # G:A:P:C:V:S
          result="${result#*:}" # strip packaging
          ;;
        *:*:*)
          # G:A:P:V:S
          result=""
          ;;
        *:*)
          # G:A:V:C
          result="${result#*:}" # strip version
          ;;
        *)
          # G:A:V
          result=""
          ;;
      esac
      echo "${result%%:*}"
      ;;
  esac
}

# Converts the given GAV into a path in the local repository cache.
repoPath() {
  local gPath="$(echo "$(groupId "$1")" | tr :. /)"
  local aPath="$(artifactId "$1")"
  local vPath="$(version "$1")"
  echo "$repoBase/$gPath/$aPath/$vPath"
}

# Gets the path to the given GAV's POM file in the local repository cache.
pomPath() {
  local pomFile="$(artifactId "$1")-$(version "$1").pom"
  echo "$(repoPath "$1")/$pomFile"
}

# Fetches the POM for the given GAV into the local repository cache.
downloadPOM() {
  local g="$(groupId "$1")"
  local a="$(artifactId "$1")"
  local v="$(version "$1")"
  debug "mvn dependency:get \\
  -DrepoUrl=\"$remoteRepos\" \\
  -DgroupId=\"$g\" \\
  -DartifactId=\"$a\" \\
  -Dversion=\"$v\" \\
  -Dpackaging=pom"
  mvn dependency:get \
    -DrepoUrl="$remoteRepos" \
    -DgroupId="$g" \
    -DartifactId="$a" \
    -Dversion="$v" \
    -Dpackaging=pom > /dev/null ||
  die "Problem fetching $g:$a:$v from $remoteRepos" 4
}

# Gets the POM path for the given GAV, ensuring it exists locally.
pom() {
  local pomPath="$(pomPath "$1")"
  test -f "$pomPath" || downloadPOM "$1"
  test -f "$pomPath" || die "Cannot access POM: $pomPath" 9
  echo "$pomPath"
}

# For the given XML file on disk ($1), gets the value of the
# specified XPath expression of the form "//$2/$3/$4/...".
xpath() {
  local xmlFile="$1"
  shift
  local expression="$@"
  local xpath="/"
  while [ $# -gt 0 ]
  do
    # NB: Ignore namespace issues; see: http://stackoverflow.com/a/8266075
    xpath="$xpath/*[local-name()='$1']"
    shift
  done
  local value=$(xmllint --xpath "$xpath" "$xmlFile" 2> /dev/null |
    sed -E 's/^[^>]*>(.*)<[^<]*$/\1/')
  debug "xpath $xmlFile $expression -> $value"
  echo "$value"
}

# For the given GAV ($1), recursively gets the value of the
# specified XPath expression of the form "//$2/$3/$4/...".
pomValue() {
  local pomPath="$(pom "$1")"
  test "$pomPath" || die "Cannot discern POM path for $1" 6
  shift
  local value="$(xpath "$pomPath" $@)"
  if [ "$value" ]
  then
    echo "$value"
  else
    # Path not found in POM; look in the parent POM.
    local pg="$(xpath "$pomPath" project parent groupId)"
    if [ "$pg" ]
    then
      # There is a parent POM declaration in this POM.
      local pa="$(xpath "$pomPath" project parent artifactId)"
      local pv="$(xpath "$pomPath" project parent version)"
      pomValue "$pg:$pa:$pv" $@
    fi
  fi
}

# Gets the SCM URL for the given GAV.
scmURL() {
  pomValue "$1" project scm connection | sed 's/^scm:git://' |
    sed 's_git:\(//github.com/\)_https:\1_'
}

# Gets the SCM tag for the given GAV.
scmTag() {
  local tag=$(pomValue "$1" project scm tag)
  if [ -z "$tag" -o "$tag" = "HEAD" ]
  then
    # The <scm><tag> value was not set properly,
    # so we try to guess the tag naming scheme. :-/
    warn "$1: improper scm tag value; scanning remote tags..."
    local a=$(artifactId "$1")
    local v=$(version "$1")
    local scmURL="$(scmURL "$1")"
    # TODO: Avoid network use. We can scan the locally cached repo.
    # But this gets complicated when the locally cached repo is
    # out of date, and the needed tag is not there yet...
    debug "git ls-remote --tags \"$scmURL\" | sed 's/.*refs\/tags\///'"
    local allTags="$(git ls-remote --tags "$scmURL" | sed 's/.*refs\/tags\///' ||
      error "$1: Invalid scm url: $scmURL")"
    for tag in "$a-$v" "$v" "v$v"
    do
      echo "$allTags" | grep -q "^$tag$" && {
        info "$1: inferred tag: $tag"
        echo "$tag"
        return
      }
    done
    error "$1: inscrutable tag scheme"
  else
    echo "$tag"
  fi
}

# Ensures the source code for the given GAV exists in the melting-pot
# structure, and is up-to-date with the remote. Returns the directory.
resolveSource() {
  local g=$(groupId "$1")
  local a=$(artifactId "$1")
  local cachedRepoDir="$meltingPotCache/$g/$a"
  if [ ! -d "$cachedRepoDir" ]
  then
    # Source does not exist locally. Clone it into the melting pot cache.
    local scmURL="$(scmURL "$1")"
    test "$scmURL" || die "$1: cannot glean SCM URL" 10
    info "$1: cached repository not found; cloning from remote: $scmURL"
    debug "git clone --bare \"$scmURL\" \"$cachedRepoDir\""
    git clone --bare "$scmURL" "$cachedRepoDir" 2> /dev/null ||
      die "$1: could not clone project source from $scmURL" 3
  fi

  # Check whether the needed branch/tag exists.
  local scmBranch
  test "$2" && scmBranch="$2" || scmBranch="$(scmTag "$1")"
  test "$scmBranch" || die "$1: cannot glean SCM tag" 14
  debug "git ls-remote \"file://$cachedRepoDir\" | grep -q \"\brefs/tags/$scmBranch$\""
  git ls-remote "file://$cachedRepoDir" | grep -q "\brefs/tags/$scmBranch$" || {
    # Couldn't find the scmBranch as a tag in the cached repo. Either the
    # tag is new, or it's not a tag ref at all (e.g. it's a branch).
    # So let's update from the original remote repository.
    info "$1: local tag not found for ref '$scmBranch'"
    info "$1: updating cached repository: $cachedRepoDir"
    cd "$cachedRepoDir"
    debug "git fetch --tags"
    if [ "$debug" ]
    then
      git fetch --tags
    else
      git fetch --tags > /dev/null
    fi
    cd - > /dev/null
  }

  # Shallow clone the source at the given version into melting-pot structure.
  local destDir="$g/$a"
  debug "git clone \"file://$cachedRepoDir\" --branch \"$scmBranch\" --depth 1 \"$destDir\""
  git clone "file://$cachedRepoDir" --branch "$scmBranch" --depth 1 "$destDir" 2> /dev/null ||
    die "$1: could not clone branch '$scmBranch' from local cache" 15

  # Now verify that the cloned pom.xml contains the expected version!
  local expectedVersion=$(version "$1")
  local actualVersion=$(xpath "$destDir/pom.xml" project version)
  test "$expectedVersion" = "$actualVersion" ||
    warn "$1: POM contains wrong version: $actualVersion"

  echo "$destDir"
}

# Gets the list of dependencies for the project in the CWD.
deps() {
  cd "$1" || die "No such directory: $1" 16
  debug "mvn -DincludeScope=runtime -B dependency:list"
  local depList="$(mvn -DincludeScope=runtime -B dependency:list)" ||
    die "Problem fetching dependencies!" 5
  echo "$depList" | grep '^\[INFO\]    [^ ]' |
    sed 's/\[INFO\]    //' | sed 's/ .*//' | sort
  cd - > /dev/null
}

# Checks whether the given GA(V) matches the specified filter pattern.
gaMatch() {
  local ga="$1"
  local filter="$2"
  local g="$(groupId "$ga")"
  local a="$(artifactId "$ga")"
  local fg="$(groupId "$filter")"
  local fa="$(artifactId "$filter")"
  test "$fg" = "$g" -o "$fg" = "*" || return
  test "$fa" = "$a" -o "$fa" = "*" || return
  echo 1
}

# Determines whether the given GA(V) version is being overridden.
isChanged() {
  local IFS=","

  local change
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
  local exclude
  for exclude in $excludes
  do
    test "$(gaMatch "$1" "$exclude")" && return
  done

  # ensure GA is included
  test -z "$includes" && echo 1 && return
  local include
  for include in $includes
  do
    test "$(gaMatch "$1" "$include")" && echo 1 && return
  done
}

# Deletes components which do not depend on a changed GAV.
pruneReactor() {
  local dir
  for dir in */*
  do
    info "Checking relevance of component $dir"
    local deps="$(deps "$dir")"
    test "$deps" || die "Cannot glean dependencies for '$dir'" 8

    # Determine whether the component depends on a changed GAV.
    local keep
    unset keep
    local dep
    for dep in $deps
    do
      test "$(isChanged "$dep")" && keep=1 && break
    done

    # If the component is irrelevant, prune it.
    if [ -z "$keep" ]
    then
      info "Pruning irrelevant component: $dir"
      rm -rf "$dir"
    fi
  done
}

# Tests if the given directory contains the appropriate source code.
isProject() {
  local a="$(xpath "$1/pom.xml" project artifactId)"
  test "$1" = "LOCAL/PROJECT" -o "$a" = "$(basename "$1")" && echo 1
}

# Generates melt.sh, covering all projects in the current directory.
generateMeltScript() {
  echo '#!/bin/sh'                                                    > melt.sh
  echo 'trap "exit" INT'                                             >> melt.sh
  echo 'echo "Melting the pot..."'                                   >> melt.sh
  echo 'dir=$(cd "$(dirname "$0")" && pwd)'                          >> melt.sh
  echo 'failCount=0'                                                 >> melt.sh
  echo 'for f in \'                                                  >> melt.sh
  local dir
  for dir in */*
  do
    if [ "$(isProject "$dir")" ]
    then
      echo "  $dir \\"                                               >> melt.sh
    else
      # Check for a child component of a multi-module project.
      local childDir="$dir/$(basename "$dir")"
      test "$(isProject "$childDir")" &&
        echo "  $childDir \\"                                        >> melt.sh
    fi
  done
  echo                                                               >> melt.sh
  echo 'do'                                                          >> melt.sh
  echo '  if [ "$("$dir/prior-success.sh" "$f")" ]'                  >> melt.sh
  echo '  then'                                                      >> melt.sh
  echo '    echo "[SKIPPED] $f (prior success)"'                     >> melt.sh
  echo '    continue'                                                >> melt.sh
  echo '  fi'                                                        >> melt.sh
  echo '  cd "$f"'                                                   >> melt.sh
  echo '  "$dir/build.sh" >build.log 2>&1 && {'                      >> melt.sh
  echo '    echo "[SUCCESS] $f"'                                     >> melt.sh
  echo '    "$dir/record-success.sh" "$f"'                           >> melt.sh
  echo '  } || {'                                                    >> melt.sh
  echo '    echo "[FAILURE] $f"'                                     >> melt.sh
  echo '    failCount=$((failCount+1))'                              >> melt.sh
  echo '  }'                                                         >> melt.sh
  echo '  cd - >/dev/null'                                           >> melt.sh
  echo 'done'                                                        >> melt.sh
  echo 'test "$failCount" -gt 255 && failCount=255'                  >> melt.sh
  echo 'exit "$failCount"'                                           >> melt.sh
  chmod +x melt.sh
}

# Generates helper scripts, including prior-success.sh and record-success.sh.
generateHelperScripts() {
  cat <<\PRIOR > prior-success.sh
#!/bin/sh
test "$1" || { echo "[ERROR] Please specify project to check."; exit 1; }

stderr() { >&2 echo "$@"; }
debug() { test "$DEBUG" && stderr "[DEBUG] $@"; }
warn() { stderr "[WARNING] $@"; }

dir=$(cd "$(dirname "$0")" && pwd)

# Check build.log for BUILD SUCCESS.
buildLog="$dir/$1/build.log"
test -f "$buildLog" && tail -n6 "$buildLog" | grep -qF '[INFO] BUILD SUCCESS' && {
  echo "build.log"
  exit 0
}

# Check success.log for matching dependency configuration.
successLog="$HOME/.cache/scijava/melting-pot/$1.success.log"
test -f "$successLog" || exit 0
success=
for deps in $(cat "$successLog")
do
  debug "Checking dep config: $deps"
  mismatch=
  for dep in $(echo "$deps" | tr ',' '\n')
  do
    # g:a:p:v:s -> -Dg.a.version=v
    s=${dep##*:}
    case "$s" in
      test) continue ;; # skip test dependencies
      none) continue ;; # empty dependency config
    esac
    gapv=${dep%:*}
    g=${gapv%%:*}
    apv=${gapv#*:}
    a=${apv%%:*}
    v=${apv##*:}
    arg=" -D$g.$a.version=$v "
    if ! grep -Fq "$arg" "$dir/build.sh"
    then
      # G:A property is not set to this V.
      # Now check if the property is even declared.
      if grep -Fq " -D$g.$a.version=" "$dir/build.sh"
      then
        # G:A version is mismatched.
        debug "$dep [MISMATCH]"
        mismatch=1
        break
      else
        # G:A version is not managed.
        warn "Unmanaged dependency: $dep"
      fi
    fi
  done
  test "$mismatch" || {
    success=$deps
    break
  }
done
echo "$success"
PRIOR
  chmod +x prior-success.sh

  cat <<\RECORD > record-success.sh
#!/bin/sh
test "$1" || { echo "[ERROR] Please specify project to update."; exit 1; }

containsLine() {
  pattern=$1
  file=$2
  test -f "$file" || return
  # HACK: The obvious way to do this is:
  #
  #   grep -qxF "$pattern" "$file"
  #
  # Unfortunately, BSD grep dies with "out of memory" when the pattern is 5111
  # characters or longer. So let's do something needlessly complex instead!
  cat "$file" | while read line
  do
    test "$pattern" = "$line" && echo 1 && break
  done
}

dir=$(cd "$(dirname "$0")" && pwd)
buildLog="$dir/$1/build.log"
test -f "$buildLog" || exit 1
successLog="$HOME/.cache/scijava/melting-pot/$1.success.log"
mkdir -p "$(dirname "$successLog")"

# Record dependency configuration of successful build.
deps=$(grep '^\[INFO\]    ' "$buildLog" |
  sed -e 's/^.\{10\}//' -e 's/ -- .*//' -e 's/ (\([^)]*\))/-\1/' |
  sort | tr '\n' ',')
if [ -z "$(containsLine "$deps" "$successLog")" ]
then
  # NB: *Prepend*, rather than append, the new successful configuration.
  # We do this because it is more likely this new configuration will be
  # encountered again in the future, as dependency versions are highly
  # likely to repeatedly increment, rather than moving backwards.
  echo "$deps" > "$successLog".new
  test -f "$successLog" && cat "$successLog" >> "$successLog".new
  mv -f "$successLog".new "$successLog"
fi
RECORD
  chmod +x record-success.sh
}

# Creates and tests an appropriate multi-module reactor for the given project.
# All relevant dependencies which match the inclusion criteria are linked into
# the multi-module build, with each changed GAV overridding the originally
# specified version for the corresponding GA.
meltDown() {
  # Fetch the project source code.
  if [ -d "$1" ]
  then
    # Use local directory for the specified project.
    test -d "$1" || die "No such directory: $1" 11
    test -f "$1/pom.xml" || die "Not a Maven project: $1" 12
    info "Local Maven project: $1"
    mkdir -p "LOCAL"
    local projectDir="LOCAL/PROJECT"
    ln -s "$1" "$projectDir"
  else
    # Treat specified project as a GAV.
    info "Fetching project source"
    local projectDir=$(resolveSource "$1" "$branch")
    test $? -eq 0 || exit $?
  fi

  # Get the project dependencies.
  info "Determining project dependencies"
  local deps="$(deps "$projectDir")"
  test "$deps" || die "Cannot glean project dependencies" 7

  # Generate helper scripts. We need prior-success.sh
  # to decide whether to include each component.
  generateHelperScripts

  local args="-Denforcer.skip"

  # Process the dependencies.
  info "Processing project dependencies"
  local dep
  for dep in $deps
  do
    local g="$(groupId "$dep")"
    local a="$(artifactId "$dep")"
    local v="$(version "$dep")"
    local c="$(classifier "$dep")"
    test -z "$c" || continue # skip secondary artifacts
    local gav="$g:$a:$v"

    test -z "$(isChanged "$gav")" &&
      args="$args \\\\\n  -D$g.$a.version=$v -D$a.version=$v"
  done

  # Override versions of changed GAVs.
  info "Processing changed components"
  local TLS=,
  local gav
  for gav in $changes
  do
    local a="$(artifactId "$gav")"
    local v="$(version "$gav")"
    args="$args \\\\\n  -D$a.version=$v"
  done
  unset TLS

  # Generate build script.
  info "Generating build.sh script"
  echo "#!/bin/sh" > build.sh
  echo "mvn $args \\\\\n  dependency:list test \$@" >> build.sh
  chmod +x build.sh

  # Clone source code.
  info "Cloning source code"
  for dep in $deps
  do
    local g="$(groupId "$dep")"
    local a="$(artifactId "$dep")"
    local v="$(version "$dep")"
    local c="$(classifier "$dep")"
    test -z "$c" || continue # skip secondary artifacts
    local gav="$g:$a:$v"
    if [ "$(isIncluded "$gav")" ]
    then
      if [ "$(./prior-success.sh "$g/$a")" ]
      then
        info "$g:$a: skipping version $v due to prior successful build"
        continue
      fi
      info "$g:$a: resolving source for version $v"
      resolveSource "$gav" >/dev/null
    fi
  done

  # Prune the build, if applicable.
  test "$prune" && pruneReactor

  # Generate melt script.
  info "Generating melt.sh script"
  generateMeltScript

  # Build everything.
  if [ "$skipBuild" ]
  then
    info "Skipping the build; run melt.sh to do it."
  else
    info "Building the project!"
    # NB: All code is fresh; no need to clean.
    sh melt.sh || die "Melt failed" 13
  fi

  info "Melt complete: $1"
}

# -- Main --

verifyPrereqs
parseArguments $@
createDir "$outputDir"
meltDown "$project"
