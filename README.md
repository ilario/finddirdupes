# finddirdupes
Finds duplicate folders

Written in shell, mainly as an excercise. The only available alternative I am aware of (rmlint, written in C) is much faster, as shell is very slow for these things!

First checks the size, then check the hash of folders with the same size.

Usage:

Find duplicate folders inside directory:
```
./finddirdupes.sh dir_name
```

Specify the minimum size of folders to consider, in bytes:
```
./finddirdupes.sh dir_name min_size
```

Example: analyze the folders contained in the home folder and ignore the empty ones (recommended).
```
./finddirdupes.sh ~ 10000
```

## Other alternatives

### rmlint

rmlint has a -D option which is actually really fast. Obviously, much faster than this shell script.

This script can give different results, as some things are considered differently, for example the symbolic links.

### czkawka

czkawka does not have this feature yet. Check out this ticket https://github.com/qarmin/czkawka/issues/976
