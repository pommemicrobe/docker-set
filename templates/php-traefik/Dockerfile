FROM dunglas/frankenphp

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    nodejs \
    npm \
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
    redis

# Install Composer (auto-verified, no hardcoded hash)
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Set working directory
WORKDIR /app/public

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1
