# base image
FROM alpine:3.19

# user id
ARG PUID=1001
ENV USER ts3bot

# install all pre-requisites, these will be needed always
RUN apk add --update --no-cache \
    opus-dev \
    youtube-dl \
    ffmpeg \
    unzip \
    dotnet6-runtime \
    aspnetcore6-runtime

# download and install the TS3AudioBot in the specified version and flavour
RUN mkdir -p /app \
    && cd /app \
    && echo "Fazendo o download https://splamy.de/api/nightly/projects/ts3ab/develop/download" \
    && wget https://splamy.de/api/nightly/projects/ts3ab/develop/download -O TS3AudioBot.zip \
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