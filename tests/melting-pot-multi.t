Test that recursive SCM retrieval works:

  $ sh "$TESTDIR/../melting-pot.sh" sc.fiji:TrakEM2_:1.0f -r http://maven.imagej.net/content/groups/public -i 'sc.fiji:TrakEM2_' -v -s -d -f
  [INFO] sc.fiji:TrakEM2_:1.0f: fetching project source
  + git clone "git://github.com/trakem2/TrakEM2" --branch "TrakEM2_-1.0f" --depth 1 "sc.fiji/TrakEM2_"
  [INFO] sc.fiji:TrakEM2_:1.0f: determining project dependencies
  + mvn dependency:list
  [INFO] sc.fiji:TrakEM2_:1.0f: processing project dependencies
  [INFO] sc.fiji:TrakEM2_:1.0f: processing changed components
  [INFO] Generating aggregator POM
  [INFO] Skipping the build; the command would have been:
  [INFO] mvn -Denforcer.skip -Dnone.version= -Dmpicbg.version=1.0.1 -Djunit.version=4.11 -Dij.version=1.49p -Dhamcrest-core.version=1.3 -Dtools.version=1.4.2 -Djama.version=1.0.3 -Dmpicbg.version=1.0.1 -Dlegacy-imglib1.version=1.1.2-DEPRECATED -DFiji_Plugins.version=3.0.0 -Dlogback-core.version=1.1.1 -DVIB_.version=2.0.2 -Dmpicbg-trakem2.version=1.2.2 -Djoda-time.version=2.3 -D3D_Viewer.version=3.0.1 -Djama.version=1.0.3 -Dimglib2.version=2.2.1 -DLasso_and_Blow_Tool.version=2.0.1 -DSkeletonize3D_.version=1.0.1 -Dudunits.version=4.3.18 -Deventbus.version=1.4 -Dvecmath.version=1.5.2 -Dj3d-core-utils.version=1.5.2 -Dformats-common.version=5.0.7 -Dimagej-common.version=0.12.2 -Dgentyref.version=1.1.0 -Djai-codec.version=1.1.3 -Djgoodies-forms.version=1.7.2 -Dperf4j.version=0.9.13 -Dmpicbg_.version=1.0.1 -Dbatik.version=1.8 -Dnative-lib-loader.version=2.0.2 -Djai_imageio.version=5.0.7 -DVIB-lib.version=2.0.1 -Djgoodies-common.version=1.7.0 -Djfreechart.version=1.0.19 -Dij.version=1.49p -DbUnwarpJ_.version=2.6.2 -Dslf4j-api.version=1.7.6 -Dspecification.version=5.0.7 -Dformats-api.version=5.0.7 -Dpal-optimization.version=2.0.0 -DVectorString.version=1.0.2 -Dpostgresql.version=8.2-507.jdbc3 -Djcommon.version=1.0.23 -Dlogback-classic.version=1.1.1 -Dome-xml.version=5.0.7 -Dtools.version=1.4.2 -Dj3d-core.version=1.5.2 -DAnalyzeSkeleton_.version=2.0.4 -Djavassist.version=3.16.1-GA -DSimple_Neurite_Tracer.version=2.0.3 -Dformats-bsd.version=5.0.7 -Dfiji-lib.version=2.1.0 -Dimglib2-ij.version=2.0.0-beta-30 -Dscijava-common.version=2.39.0 -Dturbojpeg.version=5.0.7 -Dcommons-math3.version=3.4.1 -Dij1-patcher.version=0.12.0 -Dimglib2-roi.version=0.3.0 -Djython-shaded.version=2.5.3 -Dkryo.version=2.21 -Djai-core.version=1.1.3 -Dmines-jtk.version=20100113 -Dtrove4j.version=3.0.3 -Dlevel_sets.version=1.0.1 test
  [INFO] sc.fiji:TrakEM2_:1.0f: complete

  $ find melting-pot -maxdepth 2
  melting-pot
  melting-pot/pom.xml
  melting-pot/sc.fiji
  melting-pot/sc.fiji/TrakEM2_
