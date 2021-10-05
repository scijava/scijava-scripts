#!/bin/bash

#
# ci-javadoc.sh - A script to build the javadocs of SciJava-based projects
#                 automatically using a continuous integration service.
#

# The following repositories are known to use this script:
#
# - bonej-org/bonej-javadoc
# - fiji/fiji-javadoc
# - flimlib/flimlib-javadoc
# - imagej/imagej-javadoc
# - imglib/imglib2-javadoc
# - scifio/scifio-javadoc
# - scenerygraphics/sciview-javadoc
# - scijava/java3d-javadoc
# - scijava/scijava-javadoc
# - uw-loci/loci-javadoc

# Wait for a launched background command to complete, emitting
# an occasional message to avoid long periods without output.
# Return the same exit code as the launched command.
keep_alive() {
	pid="$1"
	if [ "$pid" = "" ]
	then
		echo "[ERROR] No PID given"
		return
	fi
	i=0
	while kill -0 "$pid" 2>/dev/null; do
		i=$((i+1))
		m=$((i/60))
		s=$((i%60))
		test $s -eq 0 && echo "[$m minutes elapsed]"
		sleep 1
	done
	wait "$pid"
}

ciURL=$(mvn -q -Denforcer.skip=true -Dexec.executable=echo -Dexec.args='${project.ciManagement.url}' --non-recursive validate exec:exec 2>&1)
ciRepo=${ciURL##*/}
ciPrefix=${ciURL%/*}
ciOrg=${ciPrefix##*/}
gitBranch=$(git branch --show-current) # get current branch name
if [ "$gitBranch" = main -o "$gitBranch" = master ]
then
	project=$1

	# Populate the settings.xml configuration.
	mkdir -p "$HOME/.m2"
	settingsFile="$HOME/.m2/settings.xml"
	customSettings=.github/settings.xml
	if [ -f "$customSettings" ]
	then
		cp "$customSettings" "$settingsFile"
	else
		# NB: Use maven.scijava.org as sole mirror if defined in <repositories>.
		test -f pom.xml && grep -A 2 '<repository>' pom.xml | grep -q 'maven.scijava.org' &&
			cat >"$settingsFile" <<EOL
<settings>
	<mirrors>
		<mirror>
			<id>scijava-mirror</id>
			<name>SciJava mirror</name>
			<url>https://maven.scijava.org/content/groups/public/</url>
			<mirrorOf>*</mirrorOf>
		</mirror>
	</mirrors>
</settings>
EOL
	fi

	# Emit some details useful for debugging.
	# NB: We run once with -q to suppress the download messages,
	# then again without it to emit the desired dependency tree.
	mvn -B -q dependency:tree &&
	mvn -B dependency:tree &&

	echo &&
	echo "== Generating javadoc ==" &&

	# Build the javadocs.
	(mvn -B -q -Pbuild-javadoc) &
	keep_alive $! &&
	test -d target/apidocs &&
	# Strip out date stamps, to avoid spurious changes being committed.
	sed -i'' -e '/\(<!-- Generated by javadoc \|<meta name="date" \)/d' $(find target/apidocs -name '*.html') &&

	echo &&
	echo "== Configuring environment ==" &&

	# Configure git settings.
	git config --global user.email "ci@scijava.org" &&
	git config --global user.name "SciJava CI" &&

	echo &&
	echo "== Updating javadoc.scijava.org repository ==" &&

	# Clone the javadoc.scijava.org repository.
	git clone --quiet --depth 1 git@github.com:scijava/javadoc.scijava.org > /dev/null &&

	# Update the relevant javadocs.
	cd javadoc.scijava.org &&
	rm -rf "$project" &&
	mv ../target/apidocs "$project" &&

	# Commit and push the changes.
	git add "$project" &&
	success=1

	test "$success" || exit 1

	git commit -m "Update $project javadocs (via $ciOrg/$ciRepo)"
	git pull --rebase &&
	git push -q origin gh-pages > /dev/null || exit 2

	echo "Update complete."
else
	echo "Skipping non-canonical branch $gitBranch"
fi
