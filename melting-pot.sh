#!/bin/sh

# melting-pot.sh - A script to build the entire SciJava software stack
#                  from the latest code on the respective master branches.

rm -rf melting-pot
mkdir melting-pot
cd melting-pot

psj_version="$(maven-helper.sh latest-version org.scijava:pom-scijava)"

echo '<?xml version="1.0" encoding="UTF-8"?>' > pom.xml
echo '<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">' >> pom.xml
echo '	<modelVersion>4.0.0</modelVersion>' >> pom.xml
echo >> pom.xml
echo '	<parent>' >> pom.xml
echo '		<groupId>org.scijava</groupId>' >> pom.xml
echo '		<artifactId>pom-scijava</artifactId>' >> pom.xml
echo "		<version>$psj_version</version>" >> pom.xml
echo "		<relativePath />" >> pom.xml
echo '	</parent>' >> pom.xml
echo >> pom.xml
echo '	<artifactId>melting-pot</artifactId>' >> pom.xml
echo '	<packaging>pom</packaging>' >> pom.xml
echo >> pom.xml
echo '	<name>SciJava Uber Build</name>' >> pom.xml
echo >> pom.xml
echo '	<modules>' >> pom.xml

for repo in $(sj-hierarchy.pl -g)
do
	git clone $repo --depth 1
	module=${repo##*/}
	module=${module%.git}
	echo "		<module>$module</module>" >> pom.xml
done

echo '	</modules>' >> pom.xml
echo
echo '</project>' >> pom.xml

mvn -Pdev.scijava,dev.imglib2,dev.scifio,dev.imagej validate
