# Stage 1 - Build Frontend (Vite)
FROM node:18 AS frontend
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2 - Backend (Laravel + PHP + Composer)
FROM php:8.2-fpm AS backend

# Install system dependencies and MongoDB extension
RUN apt-get update && apt-get install -y \
    git curl unzip libzip-dev zip \
    && docker-php-ext-install mbstring zip \
    && curl -fsSL https://pecl.php.net/get/mongodb -o /tmp/mongodb.tgz \
    && tar -xzf /tmp/mongodb.tgz -C /tmp \
    && rm /tmp/mongodb.tgz \
    && cd /tmp/mongodb-* \
    && apt-get install -y build-essential autoconf pkg-config \
    && phpize \
    && ./configure \
    && make \
    && make install \
    && docker-php-ext-enable mongodb \
    && apt-get remove -y build-essential autoconf pkg-config \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/mongodb-*

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

# Copy app files
COPY . .

# Copy built frontend from Stage 1
COPY --from=frontend /app/public/build ./public/build

# Install PHP dependencies
RUN composer install --no-dev --optimize-autoloader

# Laravel setup
RUN php artisan config:clear && \
    php artisan route:clear && \
    php artisan view:clear

CMD ["php-fpm"]
