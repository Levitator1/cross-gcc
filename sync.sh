#!/usr/bin/bash

# user@host
# no trailing colon or path
SOURCE=$1

TARGET_DIR=$2
SUBDIRS="/usr/include /lib /usr/lib"

for DIR in $SUBDIRS
do
	REMOTE_DIR="$SOURCE:$DIR"
	echo Processing: $REMOTE_DIR
	LOCAL_DIR=$TARGET_DIR/$DIR
	mkdir -p $LOCAL_DIR || { echo Failed creating local dir: $LOCAL_DIR; exit -1; }
	rsync -av -e ssh $REMOTE_DIR `dirname $LOCAL_DIR` --exclude /lib/modules || { echo Failed rsync; exit -1; }
done

echo Done
echo

