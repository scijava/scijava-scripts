Test that the '--prune' flag works as intended:

  $ sh "$TESTDIR/../melting-pot.sh" net.imagej:imagej-common:0.15.1 -r https://maven.scijava.org/content/groups/public -c org.scijava:scijava-common:2.44.2 -i 'org.scijava:*,net.imagej:*,net.imglib2:*' -p -v -f -s
  [INFO] net.imagej:imagej-common:0.15.1: fetching project source
  [INFO] net.imagej:imagej-common:0.15.1: determining project dependencies
  [INFO] net.imagej:imagej-common:0.15.1: processing project dependencies
  [INFO] net.imagej:imagej-common:0.15.1: imglib2-roi: fetching component source
  [INFO] net.imagej:imagej-common:0.15.1: imglib2: fetching component source
  [INFO] net.imagej:imagej-common:0.15.1: processing changed components
  [INFO] Checking relevance of component net.imagej/imagej-common
  [INFO] Checking relevance of component net.imglib2/imglib2
  [INFO] Pruning irrelevant component: net.imglib2/imglib2
  [INFO] Checking relevance of component net.imglib2/imglib2-roi
  [INFO] Pruning irrelevant component: net.imglib2/imglib2-roi
  [INFO] Generating aggregator POM
  [INFO] Skipping the build; the command would have been:
  [INFO] mvn -Denforcer.skip -Dgentyref.version=1.1.0 -Dudunits.version=4.3.18 -Djunit.version=4.11 -Dimglib2-roi.version=0.3.0 -Dimglib2.version=2.2.1 -Dtrove4j.version=3.0.3 -Deventbus.version=1.4 -Dhamcrest-core.version=1.3 -Dscijava-common.version=2.44.2 test
  [INFO] net.imagej:imagej-common:0.15.1: complete

  $ find melting-pot -maxdepth 2 | sort
  melting-pot
  melting-pot/net.imagej
  melting-pot/net.imagej/imagej-common
  melting-pot/net.imglib2
  melting-pot/pom.xml
