#!/bin/bash
# Uncomment this to see debug output
#set -x
set -u -e -o pipefail

shopt -s dotglob nullglob

umask 0000

# Copy files if they not exist
if test \( \! -f index.php \) -o \( \! -d wp-admin \); then
	rm -r -f *
	cp -R --no-preserve=all -t . /usr/src/wordpress/*
	chown -R "$(stat -c '%U:%G' /usr/src/wordpress/index.php)" *
fi

APACHE_CONFDIR="/etc/apache2"
APACHE_ENVVARS="$APACHE_CONFDIR/envvars"
if test -r "$APACHE_ENVVARS"; then
	. "$APACHE_ENVVARS"
fi
: "${APACHE_RUN_DIR:=/var/run/apache2}"
: "${APACHE_PID_FILE:=$APACHE_RUN_DIR/apache2.pid}"
rm -f "$APACHE_PID_FILE"

docker-entrypoint.sh apache2-foreground -k start
while ! test -r "$APACHE_PID_FILE"; do
	sleep 1s
done
APACHE_PID="$(< "$APACHE_PID_FILE")"
apache-notifier -p "$APACHE_PID" -s "$DOCKER_RULES_DIR"

tail -f -q -n '+1' "--pid=${APACHE_PID}" \
                   "${APACHE_LOG_DIR}/access.log" \
                   "${APACHE_LOG_DIR}/error.log" \
                   "${APACHE_LOG_DIR}/other_vhosts_access.log" \
                   "${APACHE_LOG_DIR}/modsec_audit.log"

unset -v APACHE_PID

exit 0
