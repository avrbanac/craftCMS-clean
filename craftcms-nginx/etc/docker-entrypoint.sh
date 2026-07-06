#!/bin/sh
# When run with no args (normal `docker compose up`), start the service
# stack. Otherwise exec whatever was passed, e.g.
#   docker compose run --rm craft composer create-project craftcms/craft .
set -e

if [ "$#" -eq 0 ]; then
    set -- supervisord -c /etc/supervisord.conf
fi

exec "$@"
