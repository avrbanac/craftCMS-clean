# =============================================================================
# CraftCMS nginx + php-fpm image (custom, multi-stage)
# -----------------------------------------------------------------------------
# Why not the official craftcms/nginx image?
#   * It caps at PHP 8.2 (no 8.4 tag).
#   * It ships OPcache + redis but NOT APCu, which Craft can use for caching.
# Built on Ubuntu + ppa:ondrej/php for PHP 8.4 and the full extension set,
# including apcu.  nginx + php-fpm run as `appuser` (uid/gid 1000 by default).
#
# Two build targets — pick one with `--target` (compose does this for you):
#
#   dev  (DEFAULT)  Code is NOT baked in; you bind-mount ./craftcms -> /app and
#                   edit it live (IntelliJ). uid/gid is aligned with the host so
#                   there is no chown dance. opcache re-checks files on every
#                   request, so edits take effect immediately.
#                       docker compose build              # uses target: dev
#
#   prod           The application code is COPYed in and `composer install
#                   --no-dev` runs at build time -> an immutable, self-contained
#                   image with no bind mount. opcache stops re-checking files
#                   (PHP_OPCACHE_VALIDATE_TIMESTAMPS=0) and open_basedir is
#                   restored for hardening.
#                       docker compose -f docker-compose.prod.yml build
#
# NOTE: the build context is the REPO ROOT (see docker-compose*.yml), so COPY
# paths below are prefixed with `craftcms-nginx/`. A .dockerignore keeps the
# context small.
# =============================================================================


# =============================================================================
# base — everything common to dev and prod
# =============================================================================
ARG ubuntu_version=24.04
FROM ubuntu:${ubuntu_version} AS base

ARG php_version=8.4
ARG userid=1000
ARG groupid=1000
ARG username=appuser
ARG groupname=appgroup
ARG appdir=/app

# Carry the identity into the child stages (dev/prod) without re-declaring ARGs.
ENV APP_USER=${username} \
    APP_GROUP=${groupname} \
    APP_UID=${userid} \
    APP_GID=${groupid} \
    APP_DIR=${appdir}

# -------------------------
# PHP settings (consumed by etc/php.d/60-craftcms.ini). These are the DEV
# defaults; the prod stage overrides PHP_OPCACHE_VALIDATE_TIMESTAMPS.
# -------------------------
ENV PHP_MEMORY_LIMIT=256M \
    PHP_MAX_EXECUTION_TIME=120 \
    PHP_UPLOAD_MAX_FILESIZE=50M \
    PHP_MAX_INPUT_VARS=1000 \
    PHP_POST_MAX_SIZE=50M \
    PHP_OPCACHE_ENABLE=1 \
    PHP_OPCACHE_REVALIDATE_FREQ=0 \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=1 \
    PHP_OPCACHE_MAX_ACCELERATED_FILES=10000 \
    PHP_OPCACHE_MEMORY_CONSUMPTION=128 \
    PHP_OPCACHE_MAX_WASTED_PERCENTAGE=10 \
    PHP_OPCACHE_INTERNED_STRINGS_BUFFER=16 \
    PHP_OPCACHE_FAST_SHUTDOWN=1

# Scan our extra ini dir IN ADDITION to PHP's compiled-in default (leading ':').
ENV PHP_INI_SCAN_DIR=":/etc/php.d"

# -------------------------
# Install packages and PHP
# -------------------------
RUN export DEBIAN_FRONTEND=noninteractive \
    && apt update -y \
    && apt install -y --no-install-recommends software-properties-common curl unzip gnupg2 lsb-release ca-certificates \
    && add-apt-repository ppa:ondrej/php \
    && apt update -y \
    && apt install -y --no-install-recommends \
        nginx \
        supervisor \
        php${php_version}-apcu \
        php${php_version}-bcmath \
        php${php_version}-cli \
        php${php_version}-common \
        php${php_version}-curl \
        php${php_version}-fpm \
        php${php_version}-gd \
        php${php_version}-iconv \
        php${php_version}-intl \
        php${php_version}-mbstring \
        php${php_version}-mysqlnd \
        php${php_version}-opcache \
        php${php_version}-pgsql \
        php${php_version}-redis \
        php${php_version}-soap \
        php${php_version}-xml \
        php${php_version}-zip \
        postgresql-client \
    && apt upgrade -y \
    && apt autoremove -y \
    && apt clean -y \
    && rm -rf /var/lib/apt/lists/*

# -------------------------
# Install Composer (used to install Craft in dev, and to bake deps in prod)
# -------------------------
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php composer-setup.php --install-dir=/usr/local/bin --filename=composer \
    && rm composer-setup.php \
    && composer --version

# -------------------------
# Align the app user with the host user (Ubuntu 24.04 ships a default 'ubuntu'
# user at uid/gid 1000 — remove it so we can claim 1000).
# -------------------------
RUN userdel ubuntu 2>/dev/null || true \
    && groupdel ubuntu 2>/dev/null || true \
    && groupadd -g ${groupid} ${groupname} \
    && useradd --uid ${userid} --gid ${groupid} --home-dir ${appdir} --no-log-init --system ${username} \
    && mkdir -p ${appdir} && chown -R ${userid}:${groupid} ${appdir}

# -------------------------
# Configuration files (context = repo root → paths start with craftcms-nginx/)
# -------------------------
COPY craftcms-nginx/etc/supervisord.conf /etc/supervisord.conf
COPY craftcms-nginx/etc/supervisord.d /etc/supervisord.d
COPY craftcms-nginx/etc/php-fpm/php-fpm.conf /etc/php-fpm.conf
COPY craftcms-nginx/etc/php.d/60-craftcms.ini /etc/php.d/60-craftcms.ini
COPY craftcms-nginx/etc/nginx/nginx.conf /etc/nginx/nginx.conf

# Make `/usr/sbin/php-fpm` resolve to our version.
RUN update-alternatives --install /usr/sbin/php-fpm php-fpm /usr/sbin/php-fpm${php_version} 1

# Sockets, logs, PID files and permissions.
RUN install -d -o ${userid} -g ${groupid} /var/run/php /run \
    && touch /var/run/php/php-fpm.sock /run/php-fpm.pid /run/supervisord.pid \
    && mkdir -p /var/log/nginx /var/lib/nginx \
    && touch /run/nginx.pid \
    && chown -R ${userid}:${groupid} /var/run/php /run /var/log/nginx /var/lib/nginx

WORKDIR ${appdir}
EXPOSE 8080
ENTRYPOINT ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]


# =============================================================================
# dev (DEFAULT) — code is bind-mounted at runtime (./craftcms -> /app)
# =============================================================================
FROM base AS dev
USER ${APP_USER}


# =============================================================================
# prod — bake the application in and install runtime-only dependencies
# =============================================================================
FROM base AS prod

# Production opcache: don't re-stat files on every request (clear cache/restart
# the container on deploy instead). Read by etc/php.d/60-craftcms.ini.
ENV PHP_OPCACHE_VALIDATE_TIMESTAMPS=0

# Bring in the application code (regenerating vendor below, so .dockerignore
# excludes craftcms/vendor and craftcms/.env — secrets are passed at runtime).
COPY --chown=${APP_UID}:${APP_GID} craftcms/ ${APP_DIR}/

# Install production dependencies as the app user. open_basedir is NOT in place
# yet (it would block reading the composer phar), so this is added afterwards.
USER ${APP_USER}
RUN COMPOSER_HOME=/tmp/composer composer install \
        --no-dev --optimize-autoloader --no-interaction --no-progress --no-scripts \
    && rm -rf /tmp/composer

# Apply the production-only PHP hardening (open_basedir, expose_php off).
USER root
COPY craftcms-nginx/etc/php.d/90-production.ini /etc/php.d/90-production.ini
USER ${APP_USER}
