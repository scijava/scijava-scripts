#!/bin/bash

#
# ci-build.sh - A script to build and/or release SciJava-based projects
#               automatically using a continuous integration service.
#
# Optional environment variables:
#   BUILD_REPOSITORY - the repository URL running the current build

dir="$(dirname "$0")"

platform=$(uname -s)

success=0
checkSuccess() {
	# Log non-zero exit code.
	test $1 -eq 0 || echo "==> FAILED: EXIT CODE $1" 1>&2

	if [ $1 -ne 0 -a -f "$2" ]
	then
		# The operation failed and a log file was provided.
		# Do some heuristics, because we like being helpful!
		javadocErrors=$(grep error: "$2")
		generalErrors=$(grep -i '\b\(errors\?\|fail\|failures\?\)\b' "$2")
		if [ "$javadocErrors" ]
		then
			echo
			echo '/----------------------------------------------------------\'
			echo '| ci-build.sh analysis: I noticed probable javadoc errors: |'
			echo '\----------------------------------------------------------/'
			echo "$javadocErrors"
		elif [ "$generalErrors" ]
		then
			echo
			echo '/-------------------------------------------------------\'
			echo '| ci-build.sh analysis: I noticed the following errors: |'
			echo '\-------------------------------------------------------/'
			echo "$generalErrors"
		else
			echo
			echo '/----------------------------------------------------------------------\'
			echo '| ci-build.sh analysis: I see no problems in the operation log. Sorry! |'
			echo '\----------------------------------------------------------------------/'
			echo
		fi
	fi

	# Record the first non-zero exit code.
	test $success -eq 0 && success=$1
}

# Credit: https://stackoverflow.com/a/12873723/1207769
escapeXML() {
	echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

mavenEvaluate() {
	mvn -B -U -q -Denforcer.skip=true -Dexec.executable=echo -Dexec.args="$1" --non-recursive validate exec:exec 2>&1
}

# Build Maven projects.
if [ -f pom.xml ]; then
	echo ::group::"= Maven build ="

	# --== MAVEN SETUP ==--

	echo
	echo "== Configuring Maven =="

	# NB: Suppress "Downloading/Downloaded" messages.
	# See: https://stackoverflow.com/a/35653426/1207769
	export MAVEN_OPTS="$MAVEN_OPTS -Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn"

	# Populate the settings.xml configuration.
	mkdir -p "$HOME/.m2"
	settingsFile="$HOME/.m2/settings.xml"
	customSettings=.ci/settings.xml
	if [ "$OSSRH_USER" -o "$OSSRH_PASS" ]; then
		echo "[WARNING] Obsolete OSSRH vars detected. Secrets may need updating to deploy to Maven Central."
	fi
	if [ -f "$customSettings" ]; then
		cp "$customSettings" "$settingsFile"
	elif [ -z "$BUILD_REPOSITORY" ]; then
		echo "Skipping settings.xml generation (no BUILD_REPOSITORY; assuming we are running locally)"
	else
		# settings.xml header
		cat >"$settingsFile" <<EOL
<settings>
	<servers>
EOL
		# settings.xml scijava servers
		if [ "$MAVEN_USER" -a "$MAVEN_PASS" ]; then
			cat >>"$settingsFile" <<EOL
		<server>
			<id>scijava.releases</id>
			<username>$MAVEN_USER</username>
			<password>$(escapeXML "$MAVEN_PASS")</password>
		</server>
		<server>
			<id>scijava.snapshots</id>
			<username>$MAVEN_USER</username>
			<password>$(escapeXML "$MAVEN_PASS")</password>
		</server>
EOL
		else
			echo "[WARNING] Skipping settings.xml scijava servers (no MAVEN deployment credentials)."
		fi
		# settings.xml central server
		if [ "$CENTRAL_USER" -a "$CENTRAL_PASS" ]; then
			cat >>"$settingsFile" <<EOL
		<server>
			<id>central</id>
			<username>$CENTRAL_USER</username>
			<password>$(escapeXML "$CENTRAL_PASS")</password>
		</server>
EOL
		else
			echo "[WARNING] Skipping settings.xml central server (no CENTRAL deployment credentials)."
		fi
		cat >>"$settingsFile" <<EOL
	</servers>
EOL
		# settings.xml GPG profile
		if [ "$GPG_KEY_NAME" -a "$GPG_PASSPHRASE" ]; then
			cat >>"$settingsFile" <<EOL
	<profiles>
		<profile>
			<id>gpg</id>
			<activation>
				<file>
					<exists>$HOME/.gnupg</exists>
				</file>
			</activation>
			<properties>
				<gpg.keyname>$GPG_KEY_NAME</gpg.keyname>
				<gpg.passphrase>$(escapeXML "$GPG_PASSPHRASE")</gpg.passphrase>
			</properties>
		</profile>
	</profiles>
EOL
		else
			echo "[WARNING] Skipping settings.xml gpg profile (no GPG credentials)."
		fi
		# settings.xml footer
		cat >>"$settingsFile" <<EOL
</settings>
EOL
	fi

	# --== DEPLOYMENT CHECKS ==--

	# Determine whether deploying is both possible and warranted.
	echo "Performing deployment checks"
	deployOK=

	scmURL=$(mavenEvaluate '${project.scm.url}')
	result=$?
	checkSuccess $result
	if [ $result -ne 0 ]; then
		echo "No deploy -- could not extract ciManagement URL"
		echo "Output of failed attempt follows:"
		echo "$scmURL"
	else
		scmURL=${scmURL%.git}
		scmURL=${scmURL%/}
		if [ "$NO_DEPLOY" ]; then
			echo "No deploy -- the NO_DEPLOY flag is set"
		elif [ "$BUILD_REPOSITORY" -a "$BUILD_REPOSITORY" != "$scmURL" ]; then
			echo "No deploy -- repository fork: $BUILD_REPOSITORY != $scmURL"
		elif [ "$BUILD_BASE_REF" -o "$BUILD_HEAD_REF" ]; then
				echo "No deploy -- proposed change: $BUILD_HEAD_REF -> $BUILD_BASE_REF"
		else
			# Are we building a snapshot version, or a release version?
			version=$(mavenEvaluate '${project.version}')
			result=$?
			checkSuccess $result
			if [ $result -ne 0 ]; then
				echo "No deploy -- could not extract version string"
				echo "Output of failed attempt follows:"
				echo "$version"
			else
				case "$version" in
					*-SNAPSHOT)
						# Snapshot version -- ensure release.properties not present.
						if [ -f release.properties ]; then
							echo "[ERROR] Spurious release.properties file is present"
							echo "Remove the file from version control and try again."
							exit 1
						fi

						# Check for SciJava Maven repository credentials.
						if [ "$MAVEN_USER" -a "$MAVEN_PASS" ]; then
							deployOK=1
						else
							echo "No deploy -- MAVEN environment variables not available"
						fi
						;;
					*)
						# Release version -- ensure release.properties is present.
						if [ ! -f release.properties ]; then
							echo "[ERROR] Release version, but release.properties not found"
							echo "You must use release-version.sh to release -- see https://imagej.net/develop/releasing"
							exit 1
						fi

						# To which repository are we releasing?
						releaseProfiles=$(mavenEvaluate '${releaseProfiles}')
						result=$?
						checkSuccess $result
						if [ $result -ne 0 ]; then
							echo "No deploy -- could not extract releaseProfiles string"
							echo "Output of failed attempt follows:"
							echo "$releaseProfiles"
						fi
						case "$releaseProfiles" in
							*deploy-to-scijava*)
								# Check for SciJava Maven repository credentials.
								if [ "$MAVEN_USER" -a "$MAVEN_PASS" ]; then
									deployOK=1
								else
									echo "[ERROR] Cannot deploy: MAVEN environment variables not available"
									exit 1
								fi
								;;
							*sonatype-oss-release*)
								# Check for Central Portal deployment credentials.
								# Deploy to Central requires GPG-signed artifacts.
								if [ "$CENTRAL_USER" -a "$CENTRAL_PASS" -a "$SIGNING_ASC" -a "$GPG_KEY_NAME" -a "$GPG_PASSPHRASE" ]; then
									deployOK=1
								else
									echo "[ERROR] Cannot deploy: CENTRAL environment variables not available"
									exit 1
								fi
								;;
							*)
								echo "Unknown deploy target -- attempting to deploy anyway"
								deployOK=1
								;;
						esac
						;;
				esac
			fi
		fi
	fi
	if [ "$deployOK" ]; then
		echo "All checks passed for artifact deployment"
	fi

	# --== Maven build arguments ==--

	BUILD_ARGS="$BUILD_ARGS -B -Djdk.tls.client.protocols=TLSv1,TLSv1.1,TLSv1.2"

	# --== GPG SETUP ==--

	if [ "$GPG_KEY_NAME" -a "$GPG_PASSPHRASE" ]; then
		# Install GPG on macOS
		if [ "$platform" = Darwin ]; then
			HOMEBREW_NO_AUTO_UPDATE=1 brew install gnupg2
		fi

		# Avoid "signing failed: Inappropriate ioctl for device" error.
		export GPG_TTY=$(tty)

		# Import the GPG signing key.
		keyFile=.ci/signingkey.asc
		if [ "$deployOK" ]; then
			echo "== Importing GPG keypair =="
			mkdir -p .ci
			echo "$SIGNING_ASC" > "$keyFile"
			ls -la "$keyFile"
			gpg --version
			gpg --batch --fast-import "$keyFile"
			checkSuccess $?
		fi

		# HACK: Use maven-gpg-plugin 3.0.1+. Avoids "signing failed: No such file or directory" error.
		maven_gpg_plugin_version=$(mavenEvaluate '${maven-gpg-plugin.version}')
		case "$maven_gpg_plugin_version" in
			0.*|1.*|2.*|3.0.0)
				echo "--> Forcing maven-gpg-plugin version from $maven_gpg_plugin_version to 3.0.1"
				BUILD_ARGS="$BUILD_ARGS -Dmaven-gpg-plugin.version=3.0.1 -Darguments=-Dmaven-gpg-plugin.version=3.0.1"
				;;
			*)
				echo "--> maven-gpg-plugin version OK: $maven_gpg_plugin_version"
				;;
		esac

		# HACK: Install pinentry helper program if missing. Avoids "signing failed: No pinentry" error.
		if ! which pinentry >/dev/null 2>&1; then
			echo '--> Installing missing pinentry helper for GPG'
			sudo apt-get install -y pinentry-tty
			# HACK: Restart the gpg agent, to notice the newly installed pinentry.
			if { pgrep gpg-agent >/dev/null && which gpgconf >/dev/null 2>&1; } then
				echo '--> Restarting gpg-agent'
				gpgconf --reload gpg-agent
				checkSuccess $?
			fi
		fi
	else
		echo "[WARNING] Skipping gpg setup (no GPG credentials)."
	fi

	# --== BUILD EXECUTION ==--

	# Run the build.
	if [ "$deployOK" -a -f release.properties ]; then
		echo
		echo "== Cutting and deploying release version =="
		BUILD_ARGS="$BUILD_ARGS release:perform"
	elif [ "$deployOK" ]; then
		echo
		echo "== Building and deploying main branch SNAPSHOT =="
		BUILD_ARGS="-Pdeploy-to-scijava $BUILD_ARGS deploy"
	else
		echo
		echo "== Building the artifact locally only =="
		BUILD_ARGS="$BUILD_ARGS install javadoc:javadoc"
	fi
	# Check the build result.
	{ mvn $BUILD_ARGS; echo $? > exit-code; } | tee mvn-log
	checkSuccess "$(cat exit-code)" mvn-log

	# --== POST-BUILD ACTIONS ==--

	# Dump logs for any failing unit tests.
	if [ -d target/surefire-reports ]
	then
		find target/surefire-reports -name '*.txt' | while read report
		do
			if grep -qF 'FAILURE!' "$report"
			then
				echo
				echo "[$report]"
				cat "$report"
			fi
		done
	fi

	if [ "$deployOK" -a "$success" -eq 0 ]; then
		echo
		echo "== Invalidating SciJava Maven repository cache =="
		curl -fsLO https://raw.githubusercontent.com/scijava/scijava-scripts/bdd932af4c4816f88cb6a52cdd7449f175934634/maven-helper.sh &&
			gav=$(sh maven-helper.sh gav-from-pom pom.xml) &&
			ga=${gav%:*} &&
			echo "--> Artifact to invalidate = $ga" &&
			echo "machine maven.scijava.org" >"$HOME/.netrc" &&
			echo "        login $MAVEN_USER" >>"$HOME/.netrc" &&
			echo "        password $MAVEN_PASS" >>"$HOME/.netrc" &&
			sh maven-helper.sh invalidate-cache "$ga"
		checkSuccess $?
	fi

	echo ::endgroup::
fi

# Execute Jupyter notebooks.
if which jupyter >/dev/null 2>&1; then
	echo ::group::"= Jupyter notebooks ="
	# NB: This part is fiddly. We want to loop over files even with spaces,
	# so we use the "find ... | while read ..." idiom.
	# However, that runs the piped expression in a subshell, which means
	# that any updates to the success variable will not persist outside
	# the loop. So we store non-zero success values into a temporary file,
	# then capture the value back into the parent shell's success variable.
	find . -name '*.ipynb' | while read nbf
	do
		echo
		echo "== $nbf =="
		jupyter nbconvert --to python --stdout --execute "$nbf"
		checkSuccess $?
		test "$success" -eq 0 || echo "$success" > success.tmp
	done
	test -f success.tmp && success=$(cat success.tmp) && rm success.tmp
	echo ::endgroup::
fi

exit $success
