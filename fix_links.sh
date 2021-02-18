#!/usr/bin/bash

# Finds all of the absolute symlinks in a tree $1 and replaces their target with $1/target
# but only if the latter is a valid target

#$1 = path of directory tree to fix up

TREE=`realpath -e "$1"` || { echo "Tree argument $1 is not found"; exit -1; }
echo "Adjusting tree: $TREE"

for f in `find $TREE`
do
	f=`realpath -ms "$f"`
	OLD_DEST=`readlink "$f"`
	# is it a symlink and does its target start with '/'?
	if [ -L "$f" ] && ! [ -z `echo "$OLD_DEST" | grep '^/.*'` ]; then
		NEW_DEST="$TREE""$OLD_DEST"
		echo "Link $f -> $OLD_DEST -> $NEW_DEST"
		NEW_DEST=$(realpath -e --relative-to=`dirname "$f"` "$NEW_DEST") || { echo 	WARNING: Updated symlink target would also be invalid, so not updated; continue; }

		if ln -sfv "$NEW_DEST" "$f"; then
			echo "SUCCESS"
		else
			echo "ERROR"
		fi
	fi
done
echo
