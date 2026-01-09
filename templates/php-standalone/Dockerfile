# FrankenPHP with PHP 8.4 (latest stable)
# https://hub.docker.com/r/dunglas/frankenphp
FROM dunglas/frankenphp:php8.4-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    zip \
    unzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN install-php-extensions \
    pdo_mysql \
    gd \
    intl \
    zip \
    opcache \
    mysqli \
    redis \
    bcmath \
    exif \
    pcntl \
    sockets \
    imagick \
    gettext

# Install Composer (latest version)
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Install Node.js 24 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app/public

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1
