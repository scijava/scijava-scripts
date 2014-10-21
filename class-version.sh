#!/bin/sh

# class-version.sh - find the Java version which wrote a JAR file

for jar in "$@"
do
  # find the first class of the JAR
  class="$(jar tf "$jar" | grep '\.class' | head -n 1 | sed 's/\//./g' | sed 's/\.class$//')"
  info="$(javap -verbose -classpath "$jar" "$class")"

  # extract major.minor version
  minor="$(echo "$info" | grep 'minor version: ' | sed 's/.*minor version: //')"
  major="$(echo "$info" | grep 'major version: ' | sed 's/.*major version: //')"
  case $major in
    45)
      version="JDK 1.1"
      ;;
    46)
      version="JDK 1.2"
      ;;
    47)
      version="JDK 1.3"
      ;;
    48)
      version="JDK 1.4"
      ;;
    49)
      version="J2SE 5.0"
      ;;
    50)
      version="J2SE 6.0"
      ;;
    *)
      if [ "$major" -gt 50 ]
      then
        version="J2SE $(expr $major - 44)"
      else
        java="Unknown"
      fi
      ;;
    
  esac

  # report the results
  echo "$jar: $version ($major.$minor)"
done
