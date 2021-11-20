#/bin/sh

# check-branch.sh - Iterate over all new commits of a topic branch,
#                   recording whether the build passes or fails for each.

commits=$@

remote=$(git rev-parse --symbolic-full-name HEAD@{u})
remote=${remote#refs/remotes/}
remote=${remote%%/*}
headBranch=$(git remote show "$remote" | grep HEAD | sed 's/ *HEAD branch: //')

test "$commits" || commits=$(git rev-list HEAD "^$headBranch" | sed '1!G;h;$!d')
# NB: The sed line above reverses the order of the commits.
# See: http://stackoverflow.com/a/744093

branch=$(git rev-parse --abbrev-ref HEAD)

count=0
for commit in $commits
do
  git checkout "$commit" > /dev/null 2>&1
  mkdir -p tmp
  prefix="$(printf %04d $count)"
  filename="tmp/$prefix-$commit"
  start=$(date +%s)
  mvn clean verify > "$filename" 2>&1 && result=SUCCESS || result=FAILURE
  end=$(date +%s)
  time=$(expr "$end" - "$start")
  echo "$prefix $commit $result $time"
  count=$(expr "$count" + 1)
done

git checkout "$branch" > /dev/null 2>&1
