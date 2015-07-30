Script should fail if output directory already exists:

  $ mkdir melting-pot && sh "$TESTDIR/../melting-pot.sh" foo:bar
  [ERROR] Directory already exists: melting-pot
  [2]
