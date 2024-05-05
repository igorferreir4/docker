FROM golang:1.22.0-alpine3.19 AS builder

LABEL org.opencontainers.image.version="v1.0.1"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.title="Registrator to use with Consul"
LABEL org.opencontainers.image.url="https://github.com/igorferreir4/docker/tree/main/containers/registrator"
LABEL org.registrator.maintainer="Igor Ferreira"
LABEL org.registrator.note="Fork from Mario Ezquerro: https://github.com/mario-ezquerro/registrator"

WORKDIR /go/src/github.com/igorferreir4/registrator/
COPY . .

RUN <<END_RUN
    set -ex
    apk update
    apk upgrade
    apk add --no-cache curl git
	curl https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
	dep ensure -vendor-only
	CGO_ENABLED=0 GOOS=linux go build \
		-a -installsuffix cgo \
		-mod=mod \
		-ldflags "-X main.Version=$(cat VERSION)" \
		-o bin/registrator \
		. \
    ;
END_RUN

FROM alpine:3.19 AS final
RUN <<END_RUN
    set -ex
	apk update
	apk upgrade
	apk add --no-cache ca-certificates \
    ;
END_RUN
COPY --from=builder /go/src/github.com/igorferreir4/registrator/bin/registrator /bin/registrator

ENTRYPOINT ["/bin/registrator"]