#/bin/sh

# check-branch.sh - Iterate over all new commits of a topic branch,
#                   recording whether the build passes or fails for each.

commits=$@
test "$commits" || commits=$(git rev-list HEAD ^master | tail -r)

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
  let time="end-start"
  echo "$prefix $commit $result $time"
  let count="count+1"
done

git checkout "$branch" > /dev/null 2>&1
