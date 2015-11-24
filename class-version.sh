#!/bin/sh

# class-version.sh - find the Java version which wrote a JAR file

for jar in "$@"
do
  # find the first class of the JAR
  class="$(jar tf "$jar" | grep '\.class' | head -n 1 | sed 's/\//./g' | sed 's/\.class$//')"

  if [ -z "$class" ]
  then
    echo "$jar: No classes"
    continue
  fi

  # extract bytes 4-7
  info="$(unzip -p "$jar" "$(jar tf "$jar" | grep \.class$ | head -n 1)" | head -c 8 | hexdump -s 4 -e '4/1 "%d\n" "\n"')"
  minor1="$(echo "$info" | sed -n 1p)"
  minor2="$(echo "$info" | sed -n 2p)"
  major1="$(echo "$info" | sed -n 3p)"
  major2="$(echo "$info" | sed -n 4p)"

  # compute major.minor version
  minor="$(expr 256 \* $minor1 + $minor2)"
  major="$(expr 256 \* $major1 + $major2)"

  # derive Java version
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
