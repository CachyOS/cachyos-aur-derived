#!/bin/sh
if [ "$(id -u)" -eq 0 ]; then
	echo "It's not recommended to run XDM as root, as it can cause problems" >&2
fi
if [ -f "$HOME/.xdmanrc" ]; then
	. "$HOME/.xdmanrc"
fi
if [ -n "$XDMAN_JAVA_HOME" ]; then
	JAVA="$XDMAN_JAVA_HOME/bin/java"
else
	JAVA=java
fi
exec "$JAVA" -Dsun.java2d.xrender=false -jar /usr/share/java/xdman/xdman.jar "$@"
