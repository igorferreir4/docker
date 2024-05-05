### Add source files
FROM alpine:latest as base

WORKDIR /ci-build
ADD 7.11.4.zip /ci-build
RUN apk add --no-cache --update unzip && \
    unzip 7.11.4.zip && \
    mv focalboard-7.11.4 focalboard && \
    # Fix bug: https://github.com/mattermost/focalboard/pull/4950/commits/2186710f4750909c707f7d332f4c1917244440b4
    cd focalboard/server/services/store/sqlstore && \
    sed -i 's/Update("FileInfo")./Update("file_info")./g' ./blocks.go && \
    sed -i 's/Set("DeleteAt", model.GetMillis())./Set("delete_at", model.GetMillis())./g' ./blocks.go

### Webapp build
FROM node:16.3.0@sha256:ca6daf1543242acb0ca59ff425509eab7defb9452f6ae07c156893db06c7a9a4 as nodebuild

WORKDIR /webapp
COPY --from=base /ci-build/focalboard/webapp/ /webapp

# 'CPPFLAGS="-DPNG_ARM_NEON_OPT=0"' Needed To Avoid Bug Described in: https://github.com/imagemin/optipng-bin/issues/118#issuecomment-1019838562
# Can be Removed when Ticket will be Closed
RUN CPPFLAGS="-DPNG_ARM_NEON_OPT=0" npm install --no-optional && \
    npm run pack

### Go build
FROM golang:1.18.3@sha256:b203dc573d81da7b3176264bfa447bd7c10c9347689be40540381838d75eebef AS gobuild

WORKDIR /go/src/focalboard
COPY --from=base /ci-build/focalboard/ /go/src/focalboard

# Get target architecture 
ARG TARGETOS
ARG TARGETARCH  

RUN EXCLUDE_PLUGIN=true EXCLUDE_SERVER=true EXCLUDE_ENTERPRISE=true make server-docker os=${TARGETOS} arch=${TARGETARCH}

### Final image
FROM debian:buster-slim

RUN mkdir -p /opt/focalboard/data/files
RUN chown -R nobody:nogroup /opt/focalboard

WORKDIR /opt/focalboard

COPY --from=nodebuild --chown=nobody:nogroup /webapp/pack pack/
COPY --from=gobuild --chown=nobody:nogroup /go/src/focalboard/bin/docker/focalboard-server bin/
COPY --from=gobuild --chown=nobody:nogroup /go/src/focalboard/LICENSE.txt LICENSE.txt
COPY --from=gobuild --chown=nobody:nogroup /go/src/focalboard/docker/server_config.json config.json

USER nobody

EXPOSE 8000/tcp 9092/tcp

VOLUME /opt/focalboard/data

CMD ["/opt/focalboard/bin/focalboard-server"]