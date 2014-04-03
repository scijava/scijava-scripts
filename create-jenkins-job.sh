#!/bin/sh

# Use this script to create a Jenkins job

die () {
	echo "$*" >&2
	exit 1
}

test $# = 2 ||
die "Usage: $0 <job-name> (<config.xml> | --deploy-to-imagej <github-URL>)"

name="$1"
jenkinsurl="http://jenkins.imagej.net:8080"
createurl="$jenkinsurl/view/Fiji/createItem?name=$name"

case "$2" in
--deploy-to-imagej=*)
	name2="$(echo "$name" | tr '_' ' ')"
	url="${2#--deploy-to-imagej=}"
	config="$(cat << EOF)"
<project>
  <actions/>
  <description>Builds and deploys $name2 every time changes are pushed to the &lt;a href="$url"&gt;$name2 Git repository&lt;/a&gt;.</description>
  <logRotator class="hudson.tasks.LogRotator">
    <daysToKeep>-1</daysToKeep>
    <numToKeep>15</numToKeep>
    <artifactDaysToKeep>-1</artifactDaysToKeep>
    <artifactNumToKeep>-1</artifactNumToKeep>
  </logRotator>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.security.AuthorizationMatrixProperty>
      <permission>hudson.model.Item.Workspace:anonymous</permission>
      <permission>hudson.model.Item.Workspace:authenticated</permission>
      <permission>hudson.model.Run.Update:authenticated</permission>
      <permission>hudson.model.Item.Configure:authenticated</permission>
      <permission>hudson.scm.SCM.Tag:authenticated</permission>
      <permission>hudson.model.Item.Delete:authenticated</permission>
      <permission>hudson.model.Item.Build:authenticated</permission>
      <permission>hudson.model.Item.Read:anonymous</permission>
      <permission>hudson.model.Item.Read:authenticated</permission>
      <permission>hudson.model.Run.Delete:authenticated</permission>
    </hudson.security.AuthorizationMatrixProperty>
    <hudson.plugins.disk__usage.DiskUsageProperty plugin="disk-usage@0.23"/>
  </properties>
  <scm class="hudson.plugins.git.GitSCM" plugin="git@2.0.4">
    <configVersion>2</configVersion>
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <name>origin</name>
        <refspec>+refs/heads/*:refs/remotes/origin/*</refspec>
        <url>$url</url>
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
    <branches>
      <hudson.plugins.git.BranchSpec>
        <name>master</name>
      </hudson.plugins.git.BranchSpec>
    </branches>
    <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
    <submoduleCfg class="list"/>
    <extensions>
      <hudson.plugins.git.extensions.impl.PerBuildTag/>
    </extensions>
  </scm>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <jdk>(Default)</jdk>
  <triggers>
    <hudson.triggers.SCMTrigger>
      <spec>@yearly</spec>
      <ignorePostCommitHooks>false</ignorePostCommitHooks>
    </hudson.triggers.SCMTrigger>
  </triggers>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>git clean -dfx</command>
    </hudson.tasks.Shell>
    <hudson.tasks.Shell>
      <command>mvn -DupdateReleaseInfo=true -Pdeploy-to-imagej deploy</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers>
    <hudson.tasks.ArtifactArchiver>
      <artifacts>**/target/*.jar</artifacts>
      <latestOnly>false</latestOnly>
      <allowEmptyArchive>false</allowEmptyArchive>
    </hudson.tasks.ArtifactArchiver>
    <hudson.tasks.Mailer plugin="mailer@1.8">
      <recipients>imagej-builds@imagej.net</recipients>
      <dontNotifyEveryUnstableBuild>false</dontNotifyEveryUnstableBuild>
      <sendToIndividuals>true</sendToIndividuals>
    </hudson.tasks.Mailer>
    <org.jenkinsci.plugins.emotional__jenkins.EmotionalJenkinsPublisher plugin="emotional-jenkins-plugin@1.1"/>
    <hudson.plugins.ircbot.IrcPublisher plugin="ircbot@2.23">
      <targets class="empty-list"/>
      <strategy>FAILURE_AND_FIXED</strategy>
      <notifyOnBuildStart>false</notifyOnBuildStart>
      <notifySuspects>false</notifySuspects>
      <notifyCulprits>false</notifyCulprits>
      <notifyFixers>false</notifyFixers>
      <notifyUpstreamCommitters>false</notifyUpstreamCommitters>
      <buildToChatNotifier class="hudson.plugins.im.build_notify.DefaultBuildToChatNotifier" plugin="instant-messaging@1.28"/>
      <matrixMultiplier>ONLY_CONFIGURATIONS</matrixMultiplier>
      <channels/>
    </hudson.plugins.ircbot.IrcPublisher>
  </publishers>
  <buildWrappers/>
</project>
EOF
	;;
*)
	config="$(cat "$2")" ||
	die "Could not read $2"
	;;
esac

#crumb="$(curl "$jenkinsurl/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")"
curl --netrc -XPOST -H Content-Type:text/xml -d "$config" "$createurl"
