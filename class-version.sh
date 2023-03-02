#!/bin/sh

# class-version.sh - find the Java version which wrote a JAR file

class_version() {
  # extract bytes 4-7
  info=$(head -c 8 | hexdump -e '4/1 "%d\n" "\n"' | tail -n4)
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
        version="Unknown"
      fi
      ;;
  esac

  # report the results
  echo "$version ($major.$minor)"
}

first_class() {
  jar tf "$1" |
    grep '\.class$' |
    grep -v '^META-INF/' |
    grep -v 'module-info\.class' |
    head -n 1
}

for file in "$@"
do
  case "$file" in
    *.class)
      version=$(cat "$file" | class_version)
      ;;
    *.jar)
      class=$(first_class "$file")
      if [ -z "$class" ]
      then
        echo "$file: No classes"
        continue
      fi
      version=$(unzip -p "$file" "$class" | class_version)
      ;;
    *)
      >&2 echo "Unsupported file: $file"
      continue
  esac

  # report the results
  echo "$file: $version"
done
