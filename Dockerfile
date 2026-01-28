# ================================
# Stage 0 – PHP extension installer
# ================================
FROM mlocati/php-extension-installer AS php-ext-installer

# ================================
# Stage 1 – Build frontend (Vite)
# ================================
FROM node:18-alpine AS frontend

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

# ================================
# Stage 2 – Backend (Laravel + PHP + Nginx)
# ================================
FROM php:8.2-fpm-alpine

# ----------------
# System & PHP deps
# ----------------
RUN apk add --no-cache \
    git \
    curl \
    unzip \
    nginx \
    supervisor \
    libzip \
    libzip-dev \
    oniguruma-dev \
    mariadb-dev \
    $PHPIZE_DEPS

# ----------------
# PHP extensions
# ----------------
RUN docker-php-ext-install \
    mbstring \
    zip \
    pdo \
    pdo_mysql

COPY --from=php-ext-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions mongodb

RUN apk del $PHPIZE_DEPS

# ----------------
# Composer
# ----------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

# ----------------
# Copy application
# ----------------
COPY . .

# Copy built frontend assets
COPY --from=frontend /app/public/build ./public/build

# ----------------
# Install PHP deps
# ----------------
RUN composer install \
    --no-dev \
    --optimize-autoloader \
    --no-interaction

# ----------------
# Permissions
# ----------------
RUN chown -R nobody:nobody /var/www \
    && chmod -R 755 /var/www/storage \
    && chmod -R 755 /var/www/bootstrap/cache

# ----------------
# Nginx config
# ----------------
RUN mkdir -p /run/nginx && \
    printf '%s\n' \
    'server {' \
    '    listen 8080;' \
    '    server_name _;' \
    '    root /var/www/public;' \
    '    index index.php;' \
    '' \
    '    location / {' \
    '        try_files $uri $uri/ /index.php?$query_string;' \
    '    }' \
    '' \
    '    location ~ \.php$ {' \
    '        fastcgi_pass 127.0.0.1:9000;' \
    '        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;' \
    '        include fastcgi_params;' \
    '    }' \
    '}' \
    > /etc/nginx/http.d/default.conf

# ----------------
# Supervisor config
# ----------------
RUN mkdir -p /etc/supervisor.d && \
    printf '%s\n' \
    '[supervisord]' \
    'nodaemon=true' \
    '' \
    '[program:php-fpm]' \
    'command=/usr/local/sbin/php-fpm -F' \
    'autostart=true' \
    'autorestart=true' \
    'stdout_logfile=/dev/stdout' \
    'stderr_logfile=/dev/stderr' \
    '' \
    '[program:nginx]' \
    'command=/usr/sbin/nginx -g "daemon off;"' \
    'autostart=true' \
    'autorestart=true' \
    'stdout_logfile=/dev/stdout' \
    'stderr_logfile=/dev/stderr' \
    > /etc/supervisor.d/supervisord.ini

EXPOSE 8080

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor.d/supervisord.ini"]
