# FrankenPHP with configurable PHP version
# Available: 8.2, 8.3, 8.4
# https://hub.docker.com/r/dunglas/frankenphp
ARG PHP_VERSION=8.4
FROM dunglas/frankenphp:php${PHP_VERSION}-bookworm

# Install system dependencies + PHP extensions in fewer layers
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

# Install Node.js (for frontend build tools)
ARG NODE_JS_VERSION=24
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_JS_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -r -s /bin/false -d /app app \
    && mkdir -p /app/public \
    && chown -R app:app /app

# Set working directory
WORKDIR /app/public

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1
