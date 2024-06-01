FROM php:8.3.7-fpm-alpine3.19

# Instala as dependências necessárias
RUN apk update && apk add --no-cache \
    freetype-dev \
    libjpeg-turbo-dev \
	imagemagick-dev \
    libpng-dev \
    libzip-dev \
	libwebp-dev \
    icu-dev \
    oniguruma-dev \
    curl \
    unzip \
	bash \	
	ghostscript \
	imagemagick \
	openssl \
	libheif \
	libjxl \
	libraw \
	librsvg \
	gettext-dev \
	libintl \
	# php83-curl \
	# php83-dom \
	# php83-exif \
	# php83-fileinfo \
	# php83-intl \
	# php83-mbstring \
	# php83-openssl \
	# php83-xml \
	# php83-zip \
	# php83-opcache \
	# php83-bcmath \
	# php83-pcntl \
	# php83-mysqli \
	php83-pecl-igbinary \
	php83-pecl-apcu
	# php83-dev

# Configura e instala as extensões PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install -j$(nproc) intl \
    && docker-php-ext-install exif zip opcache mysqli pdo_mysql gettext

RUN docker-php-ext-configure pdo_mysql --with-pdo-mysql=mysqlnd \
    && docker-php-ext-configure mysqli --with-mysqli=mysqlnd \
    && docker-php-ext-install pdo_mysql

RUN set -eux; \
	docker-php-ext-enable opcache; \
	{ \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=60'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN { \
		echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
		echo 'display_errors = Off'; \
		echo 'display_startup_errors = Off'; \
		echo 'log_errors = On'; \
		echo 'error_log = /dev/stderr'; \
		echo 'log_errors_max_len = 1024'; \
		echo 'ignore_repeated_errors = On'; \
		echo 'ignore_repeated_source = Off'; \
		echo 'html_errors = Off'; \
	} > /usr/local/etc/php/conf.d/error-logging.ini

CMD ["php-fpm"]