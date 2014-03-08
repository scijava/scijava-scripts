#!/usr/bin/jenkins-cli

/**
 * Prints author information for use by Git about the user who started a given
 * Jenkins build. Example usage in an 'Execute shell' build step:
 *
 * eval "$(jenkins-cli groovy git-info-for-job.groovy $JOB_NAME $BUILD_NUMBER)"
 */

if (this.args.length != 2) {
        throw new IllegalArgumentException("Usage: author-ident <job> <build-number>")
}

projectName = this.args[0]
buildNumber = Integer.parseInt(this.args[1])

map = jenkins.model.Jenkins.instance.getItemMap()
project = map.get(projectName)
build = project.getBuildByNumber(buildNumber)

emailMap = [
        "Curtis Rueden": "ctrueden@wisc.edu",
        "Johannes Schindelin": "johannes.schindelin@gmx.de",
        "Mark Hiner": "hinerm@gmail.com"
]

for (cause in build.getCauses()) try {
        name = cause.getUserName()
        println('GIT_AUTHOR_NAME="' + name + '"')
        println('export GIT_AUTHOR_NAME')
        email = emailMap[name]
        if (email == null) {
                email = name.toLowerCase().replaceAll(' ', '.') + '@jenkins.imagej.net'
        }
        println('GIT_AUTHOR_EMAIL="' + email + '"')
        println('export GIT_AUTHOR_EMAIL')
        break
} catch (e) { /* ignore */ }
