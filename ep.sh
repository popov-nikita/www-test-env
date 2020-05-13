#!/bin/bash
# Uncomment this to see debug output
set -x
set -u -e -o pipefail

shopt -s dotglob nullglob

# Copy files if they not exist
if test \( \! -f index.php \) -o \( \! -d wp-admin \); then
	rm -r -f *
	umask 0000
	cp -R --no-preserve=all -t . /usr/src/wordpress/*
	chown -R "$(stat -c '%U:%G' /usr/src/wordpress/index.php)" *
fi

exec docker-entrypoint.sh apache2-foreground -k start
