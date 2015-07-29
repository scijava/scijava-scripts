Test that the '--prune' flag works as intended:

  $ sh "$TESTDIR/../melting-pot.sh" net.imagej:imagej-common:0.15.1 -r http://maven.imagej.net/content/groups/public -c org.scijava:scijava-common:2.44.2 -i 'org.scijava:*,net.imagej:*,net.imglib2:*' -p -v -f -s
  [DEBUG] net.imagej:imagej-common:0.15.1: fetching project source
  [DEBUG] net.imagej:imagej-common:0.15.1: determining project dependencies
  [DEBUG] net.imagej:imagej-common:0.15.1: processing project dependencies
  [DEBUG] net.imagej:imagej-common:0.15.1: imglib2-roi: fetching component source
  [DEBUG] net.imagej:imagej-common:0.15.1: imglib2: fetching component source
  [DEBUG] net.imagej:imagej-common:0.15.1: processing changed components
  [DEBUG] Checking relevance of component net.imagej/imagej-common
  [DEBUG] Checking relevance of component net.imglib2/imglib2
  [DEBUG] Pruning irrelevant component: net.imglib2/imglib2
  [DEBUG] Checking relevance of component net.imglib2/imglib2-roi
  [DEBUG] Pruning irrelevant component: net.imglib2/imglib2-roi
  [DEBUG] Generating aggregator POM
  [DEBUG] Skipping the build; the command would have been:
  [DEBUG] mvn -Denforcer.skip -Dimglib2-roi.version=0.3.0 -Djunit.version=4.11 -Dhamcrest-core.version=1.3 -Dimglib2.version=2.2.1 -Dtrove4j.version=3.0.3 -Dgentyref.version=1.1.0 -Dudunits.version=4.3.18 -Deventbus.version=1.4 -Dscijava-common.version=2.44.2 test
  [DEBUG] net.imagej:imagej-common:0.15.1: complete

  $ find melting-pot -maxdepth 2
  melting-pot
  melting-pot/net.imagej
  melting-pot/net.imagej/imagej-common
  melting-pot/net.imglib2
  melting-pot/pom.xml
