FROM dunglas/frankenphp

# Install Node.js and npm
RUN apt-get update && apt-get install -y git nodejs npm zip unzip

# Install PHP extensions
RUN install-php-extensions \
	pdo_mysql \
	gd \
	intl \
	zip \
	opcache \
	mysqli

# Install Composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
RUN php -r "if (hash_file('sha384', 'composer-setup.php') === 'dac665fdc30fdd8ec78b38b9800061b4150413ff2e3b6f88543c636f7cd84f6db9189d43a81e5503cda447da73c7e5b6') { echo 'Installer verified'.PHP_EOL; } else { echo 'Installer corrupt'.PHP_EOL; unlink('composer-setup.php'); exit(1); }"
RUN php composer-setup.php
RUN php -r "unlink('composer-setup.php');"
RUN mv composer.phar /usr/local/bin/composer

# Set the working directory inside the container
WORKDIR /app/public
