Test that recursive SCM retrieval and multi-module projects work:

  $ sh "$TESTDIR/../melting-pot.sh" sc.fiji:TrakEM2_:1.0f -r http://maven.imagej.net/content/groups/public -i 'sc.fiji:TrakEM2_' -v -s -d -f
  [INFO] sc.fiji:TrakEM2_:1.0f: fetching project source
  \+ xmllint --xpath ".*'project'.*'scm'.*'connection'.*" ".*/sc/fiji/TrakEM2_/1.0f/TrakEM2_-1.0f.pom" (re)
  \+ xmllint --xpath ".*'project'.*'parent'.*'groupId'.*" ".*/sc/fiji/TrakEM2_/1.0f/TrakEM2_-1.0f.pom" (re)
  \+ xmllint --xpath ".*'project'.*'parent'.*'artifactId'.*" ".*/sc/fiji/TrakEM2_/1.0f/TrakEM2_-1.0f.pom" (re)
  \+ xmllint --xpath ".*'project'.*'parent'.*'version'.*" ".*/sc/fiji/TrakEM2_/1.0f/TrakEM2_-1.0f.pom" (re)
  \+ xmllint --xpath ".*'project'.*'scm'.*'connection'.*" ".*/sc/fiji/pom-trakem2/1.3.2/pom-trakem2-1.3.2.pom" (re)
  + git clone "git://github.com/trakem2/TrakEM2" --branch "TrakEM2_-1.0f" --depth 1 "sc.fiji/TrakEM2_"
  [INFO] sc.fiji:TrakEM2_:1.0f: determining project dependencies
  + mvn dependency:list
  [INFO] sc.fiji:TrakEM2_:1.0f: processing project dependencies
  [INFO] sc.fiji:TrakEM2_:1.0f: processing changed components
  [INFO] Generating aggregator POM
  + xmllint --xpath "//*[local-name()='project']/*[local-name()='artifactId']" "sc.fiji/TrakEM2_/pom.xml"
  + xmllint --xpath "//*[local-name()='project']/*[local-name()='artifactId']" "sc.fiji/TrakEM2_/TrakEM2_/pom.xml"
  [INFO] Skipping the build; the command would have been:
  [INFO] mvn -Denforcer.skip -Dbatik.version=1.8 -Dlogback-classic.version=1.1.1 -Dlogback-core.version=1.1.1 -Dkryo.version=2.21 -Dgentyref.version=1.1.0 -Djgoodies-common.version=1.7.0 -Djgoodies-forms.version=1.7.2 -Djai-codec.version=1.1.3 -Dtools.version=1.4.2 -Dtools.version=1.4.2 -Dmines-jtk.version=20100113 -Dudunits.version=4.3.18 -Djama.version=1.0.3 -Djama.version=1.0.3 -Dj3d-core-utils.version=1.5.2 -Dj3d-core.version=1.5.2 -Dvecmath.version=1.5.2 -Djai-core.version=1.1.3 -Djoda-time.version=2.3 -Djunit.version=4.11 -Dmpicbg.version=1.0.1 -Dmpicbg.version=1.0.1 -Dmpicbg_.version=1.0.1 -Dij1-patcher.version=0.12.0 -Dij.version=1.49p -Dij.version=1.49p -Dimagej-common.version=0.12.2 -Dimglib2-ij.version=2.0.0-beta-30 -Dimglib2-roi.version=0.3.0 -Dimglib2.version=2.2.1 -Dtrove4j.version=3.0.3 -Dnone.version= -Dformats-api.version=5.0.7 -Dformats-bsd.version=5.0.7 -Dformats-common.version=5.0.7 -Djai_imageio.version=5.0.7 -Dome-xml.version=5.0.7 -Dspecification.version=5.0.7 -Dturbojpeg.version=5.0.7 -Dcommons-math3.version=3.4.1 -Deventbus.version=1.4 -Dhamcrest-core.version=1.3 -Djavassist.version=3.16.1-GA -Djcommon.version=1.0.23 -Djfreechart.version=1.0.19 -Dperf4j.version=0.9.13 -Djython-shaded.version=2.5.3 -Dnative-lib-loader.version=2.0.2 -Dscijava-common.version=2.39.0 -Dslf4j-api.version=1.7.6 -Dpostgresql.version=8.2-507.jdbc3 -D3D_Viewer.version=3.0.1 -DAnalyzeSkeleton_.version=2.0.4 -DFiji_Plugins.version=3.0.0 -DLasso_and_Blow_Tool.version=2.0.1 -DSimple_Neurite_Tracer.version=2.0.3 -DSkeletonize3D_.version=1.0.1 -DVIB-lib.version=2.0.1 -DVIB_.version=2.0.2 -DVectorString.version=1.0.2 -DbUnwarpJ_.version=2.6.2 -Dfiji-lib.version=2.1.0 -Dlegacy-imglib1.version=1.1.2-DEPRECATED -Dlevel_sets.version=1.0.1 -Dmpicbg-trakem2.version=1.2.2 -Dpal-optimization.version=2.0.0 test
  [INFO] sc.fiji:TrakEM2_:1.0f: complete

  $ find melting-pot -maxdepth 2 | sort
  melting-pot
  melting-pot/pom.xml
  melting-pot/sc.fiji
  melting-pot/sc.fiji/TrakEM2_

  $ grep '<module>sc.fiji/TrakEM2_/TrakEM2_</module>' melting-pot/pom.xml
  \t\t<module>sc.fiji/TrakEM2_/TrakEM2_</module> (esc)
