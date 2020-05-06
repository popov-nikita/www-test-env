#!/bin/bash

set -x
set -u -e -o pipefail

cd "$(dirname "$0")"

DOCKER_DOCROOT='/var/www/html'
HOST_DOCROOT="$(mktemp --tmpdir=/tmp -d 'docroot.XXXXXXX')"
chmod --silent 777 "$HOST_DOCROOT"
printf 'Created temporary docroot in %s\n' "$HOST_DOCROOT"

remove_temp_docroot() {
	rm -r -f "$HOST_DOCROOT"
}
trap remove_temp_docroot EXIT

IMAGE_NAME='www-test-env'
HOST_NAME="${IMAGE_NAME}.local"
MODSECURITY_TARGZ='modsecurity-2.9.3.tar.gz'
MODSECURITY_BUILD_DIR='/modsecurity-build-root'

_is_prune=0
_it_opts=

help() {
	local prog="$(basename "$0")"

	printf 'Usage: %s [[-i|--interactive] [-p|--prune] | [-h|--help]]\n' "$prog"
	printf '       -i|--interactive    Attach pseudo TTY to STDIN of this container\n'
	printf '       -p|--prune          Remove existing image and rebuild it from scratch\n'
	printf '       -h|--help           Show this message\n'

	exit 1
}

while test $# -gt 0; do
	case "$1" in
	-p|--prune)
		if test "$(docker images -q "${IMAGE_NAME}:latest")" != ""; then
			_is_prune=1
		fi
		;;
	-i|--interactive)
		_it_opts='-i -t'
		;;
	-h|--help)
		help
		;;
	*)
		printf 'Unknown option: %s\n' "$1"
		exit 1
		;;
	esac
	shift
done

if test $_is_prune -eq 1; then
	docker rmi -f "${IMAGE_NAME}:latest"
fi

if test "$(docker images -q "${IMAGE_NAME}:latest")" = ""; then
	docker build --build-arg="MODSECURITY_TARGZ=${MODSECURITY_TARGZ}" \
	             --build-arg="MODSECURITY_BUILD_DIR=${MODSECURITY_BUILD_DIR}" \
	             -t "${IMAGE_NAME}:latest" .
fi

declare -a -r DOCKER_ARGV=(
	"docker"
	"run"
	"$_it_opts"
	"--mount"
	"\"type=bind,src=${HOST_DOCROOT},dst=${DOCKER_DOCROOT},bind-nonrecursive=true\""
	"-h"
	"\"$HOST_NAME\""
	"-w"
	"\"$DOCKER_DOCROOT\""
	"\"${IMAGE_NAME}:latest\""
)

eval "${DOCKER_ARGV[*]}"

exit 0
