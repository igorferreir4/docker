FROM alpine:3.18
## versão 3.19 não tem libssl1.1

RUN apk add --update --no-cache \
        ca-certificates \
        \
        # .NET Core dependencies
        krb5-libs \
        libgcc \
        libintl \
        libssl1.1 \
        libstdc++ \
        zlib

ENV \
    # Configure web servers to bind to port 80 when present
    ASPNETCORE_URLS=http://+:80 \
    # Enable detection of running in a container
    DOTNET_RUNNING_IN_CONTAINER=true \
    # Set the invariant mode since ICU package isn't included (see https://github.com/dotnet/announcements/issues/20)
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true

# .NET Runtime version
ENV DOTNET_VERSION=3.1.32

RUN set -eux; \
	apkArch="$(apk --print-arch)"; \
	case "$apkArch" in \
		x86_64)  binArch='x64' ;; \
		aarch64) binArch='arm64' ;; \
		*) echo >&2 "error: unsupported architecture ($apkArch)"; exit 1 ;;\
	esac; \
	wget -O dotnet.tar.gz "https://dotnetcli.azureedge.net/dotnet/Runtime/$DOTNET_VERSION/dotnet-runtime-$DOTNET_VERSION-linux-musl-${binArch}.tar.gz" \
    && mkdir -p /usr/share/dotnet \
    && tar -oxzf dotnet.tar.gz -C /usr/share/dotnet \
    && rm dotnet.tar.gz \
    && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet

# ASP.NET Core version
ENV ASPNETCORE_VERSION=3.1.32

RUN set -eux; \
	apkArch="$(apk --print-arch)"; \
	case "$apkArch" in \
		x86_64)  binArch='x64' ;; \
		aarch64) binArch='arm64' ;; \
		*) echo >&2 "error: unsupported architecture ($apkArch)"; exit 1 ;;\
	esac; \
    wget -O aspnetcore.tar.gz "https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime/$ASPNETCORE_VERSION/aspnetcore-runtime-$ASPNETCORE_VERSION-linux-musl-${binArch}.tar.gz" \	
    && tar -oxzf aspnetcore.tar.gz -C /usr/share/dotnet ./shared/Microsoft.AspNetCore.App \
    && rm aspnetcore.tar.gz

# FROM mcr.microsoft.com/dotnet/aspnet:6.0
# # igorferreir4/aspnet:3.1.30-alpine3.16.2

# user id
ARG PUID=1001
ENV USER ts3bot

# install all pre-requisites, these will be needed always
RUN apk add --update --no-cache \
    opus-dev \
    youtube-dl \
    ffmpeg \
    unzip

# download and install the TS3AudioBot in the specified version and flavour
RUN mkdir -p /app \
    && cd /app \
    && echo "Fazendo o download https://splamy.de/api/nightly/projects/ts3ab/master/download" \
    && wget https://splamy.de/api/nightly/projects/ts3ab/master/download -O TS3AudioBot.zip \
    && unzip TS3AudioBot.zip \
    && rm TS3AudioBot.zip

# add user to run under, make data directory and chown it to the ts3bot user
RUN adduser --disabled-password -u "${PUID}" "${USER}" \
    && mkdir -p /app/data \
    && chown -R "${USER}" /app/data

# set user to ts3bot, we dont want to be root from now on
USER "${USER}"

# set the work dir to data, so users can properly mount their config files to this dir with -v /host/path/to/data:/data
WORKDIR /app/data

# expose the webserver port 
EXPOSE 58913

CMD ["dotnet", "/app/TS3AudioBot.dll"]
