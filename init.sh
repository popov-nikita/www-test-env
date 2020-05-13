#!/bin/bash
# Uncomment this to see debug output
set -x
set -u -e -o pipefail

if ! type -t nc curl >/dev/null 2>&1; then
	printf 'This script requires nc and curl utilities for network operations\n'
	exit 1
fi

if ! type -t make >/dev/null 2>&1; then
	printf 'This script requires make utility\n'
	exit 1
fi

cd "$(dirname "$0")"

declare -r TCP_TEST_COM="nc -z -w 2 \"\$1\" \"\$2\" >/dev/null 2>&1"
tcp_wait() {
	printf 'Waiting for TCP %s:%s being available\n' "$1" "$2"
	while ! eval "$TCP_TEST_COM"; do
		printf '*'
		sleep 2s
	done
	printf '\n'
	printf 'TCP %s:%s is ready\n' "$1" "$2"
	return 0
}

help() {
	local prog="$(basename "$0")"

	printf 'Usage: %s [[-p|--prune] | [-h|--help]]\n' "$prog"
	printf '       -p|--prune          Remove existing image and rebuild it from scratch\n'
	printf '       -h|--help           Show this message\n'

	exit 1
}

cleanup() {
	if test -n "${WORDPRESS_DOCKER_ID:-}"; then
		docker stop "$WORDPRESS_DOCKER_ID" >/dev/null 2>&1 || true
		unset -v WORDPRESS_DOCKER_ID
	fi

	if test -n "${MARIADB_DOCKER_ID:-}"; then
		docker stop "$MARIADB_DOCKER_ID" >/dev/null 2>&1 || true
		unset -v MARIADB_DOCKER_ID
	fi
	exit 1
}
trap cleanup EXIT
#HUP INT QUIT TERM

# Load environment
declare -r ENV_FILE=environ
declare -r ENV_PREPROCESSOR=parse-environ.awk
if test -f "$ENV_FILE"; then
	eval "$(awk -f "$ENV_PREPROCESSOR" "$ENV_FILE")"
fi

if ! test -d "$HOST_DOCROOT"; then
	mkdir -p "$HOST_DOCROOT"
	chmod --silent 777 "$HOST_DOCROOT"
	printf 'Created docroot at %s\n' "$HOST_DOCROOT"
fi
HOST_DOCROOT="$(realpath "$HOST_DOCROOT")"

if ! test -d "$HOST_RULES_DIR"; then
	mkdir -p "$HOST_RULES_DIR"
	chmod --silent 777 "$HOST_RULES_DIR"
	printf 'Created rules directory at %s\n' "$HOST_RULES_DIR"
fi
HOST_RULES_DIR="$(realpath "$HOST_RULES_DIR")"

export APACHE_NOTIFIER_TARGZ
printf 'Preparing %s...\n' "$APACHE_NOTIFIER_TARGZ"
make --no-print-directory -s -C apache-notifier clean make_targz
mv -f "apache-notifier/${APACHE_NOTIFIER_TARGZ}" .

_want_prune=
while test $# -gt 0; do
	case "$1" in
	-p|--prune)
		if test -n "$(docker images -q "${IMAGE_NAME}:latest")"; then
			_want_prune='yes'
		fi
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

if test -n "$_want_prune"; then
	docker rmi -f "${IMAGE_NAME}:latest"
fi

if test -z "$(docker images -q "${IMAGE_NAME}:latest")"; then
	docker build --build-arg="MODSECURITY_TARGZ=${MODSECURITY_TARGZ}" \
	             --build-arg="APACHE_NOTIFIER_TARGZ=${APACHE_NOTIFIER_TARGZ}" \
	             --build-arg="DOCKER_RULES_DIR=${DOCKER_RULES_DIR}" \
	             --build-arg="DOCKER_DOCROOT=${DOCKER_DOCROOT}" \
	             --build-arg="BUILD_DIR=${BUILD_DIR}" \
	             -t "${IMAGE_NAME}:latest" .
fi

if test -z "$(docker images -q "${MYSQL_IMAGE_NAME}:latest")"; then
	docker image pull "${MYSQL_IMAGE_NAME}:latest"
fi

declare -a -r MARIADB_DOCKER_ARGV=(
	"docker"
	"run"
	"-d"
	"--rm"
	"-e"
	"\"MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}\""
	"-e"
	"\"MYSQL_DATABASE=${MYSQL_DATABASE}\""
	"-e"
	"\"MYSQL_ALLOW_EMPTY_PASSWORD=yes\""
	"\"${MYSQL_IMAGE_NAME}:latest\""
	"--character-set-server=utf8mb4"
	"--collation-server=utf8mb4_general_ci"
)

MARIADB_DOCKER_ID="$(eval "${MARIADB_DOCKER_ARGV[*]}")"
MARIADB_DOCKER_IP_ADDR="$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$MARIADB_DOCKER_ID")"

# MariaDB server takes too long to start-up. Need to wait here before we can proceed.
# See: https://hub.docker.com/_/mariadb:
# If there is no database initialized when the container starts,
# then a default database will be created.
# While this is the expected behavior,
# this means that it will not accept incoming connections until such initialization completes.
# This may cause issues when using automation tools,
# such as docker-compose, which start several containers simultaneously.
tcp_wait "$MARIADB_DOCKER_IP_ADDR" 3306

declare -a -r WORDPRESS_DOCKER_ARGV=(
	"docker"
	"run"
	"-d"
	"--mount"
	"\"type=bind,src=${HOST_DOCROOT},dst=${DOCKER_DOCROOT},bind-nonrecursive=true\""
	"--mount"
	"\"type=bind,src=${HOST_RULES_DIR},dst=${DOCKER_RULES_DIR},ro=true,bind-nonrecursive=true\""
	"-h"
	"\"${HOST_NAME}\""
	"-w"
	"\"${DOCKER_DOCROOT}\""
	"--rm"
	"-e"
	"\"DOCKER_DOCROOT=${DOCKER_DOCROOT}\""
	"-e"
	"\"DOCKER_RULES_DIR=${DOCKER_RULES_DIR}\""
	"-e"
	"\"WORDPRESS_DB_HOST=${MARIADB_DOCKER_IP_ADDR}\""
	"-e"
	"\"WORDPRESS_DB_USER=root\""
	"-e"
	"\"WORDPRESS_DB_PASSWORD=\""
	"-e"
	"\"WORDPRESS_DB_NAME=${MYSQL_DATABASE}\""
	"-e"
	"\"WORDPRESS_DB_CHARSET=utf8mb4\""
	"-e"
	"\"WORDPRESS_DB_COLLATE=utf8mb4_general_ci\""
	"\"${IMAGE_NAME}:latest\""
)

WORDPRESS_DOCKER_ID="$(eval "${WORDPRESS_DOCKER_ARGV[*]}")"
WORDPRESS_DOCKER_IP_ADDR="$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$WORDPRESS_DOCKER_ID")"

tcp_wait "$WORDPRESS_DOCKER_IP_ADDR" 80

declare -a -r WORDPRESS_POST_ARGS=(
	"\"weblog_title=${WP_TITLE}\""
	"\"user_name=${WP_USER}\""
	"\"admin_password=${WP_PASS}\""
	"\"admin_password2=${WP_PASS}\""
	"\"admin_email=${WP_EMAIL}\""
	"\"blog_public=0\""
)

WP_INST_CMD="curl -s"
for v in "${WORDPRESS_POST_ARGS[@]}"; do
	WP_INST_CMD="${WP_INST_CMD} --data-urlencode ${v}"
done
WP_INST_CMD="${WP_INST_CMD} \"http://${WORDPRESS_DOCKER_IP_ADDR}/wp-admin/install.php?step=2\" >/dev/null 2>&1"
(
	printf 'Performing automated WordPress install...\n'
	eval "$WP_INST_CMD" &
	CURL_PID="$!"
	while kill -n 0 "$CURL_PID" >/dev/null 2>&1; do
		printf '*'
		sleep 2s
	done
	wait "$CURL_PID"
	unset -v CURL_PID
	printf '\n'
	printf 'WordPress installed!\n'
)

printf 'DONE! Log in to http://%s/wp-login.php using these credentials:\n' "$WORDPRESS_DOCKER_IP_ADDR"
printf '    USERNAME: %s\n' "$WP_USER"
printf '    PASSWORD: %s\n' "$WP_PASS"
printf '\n'

printf 'LOGS:\n'
docker container logs --follow "$WORDPRESS_DOCKER_ID"

exit 0
