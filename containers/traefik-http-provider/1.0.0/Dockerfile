FROM golang:1.25-alpine AS builder

WORKDIR /build

COPY main.go .

RUN go mod init traefik-http-provider && \
    go get gopkg.in/yaml.v3 && \
    go mod tidy && \
    CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-w -s" -o server .

FROM gcr.io/distroless/static-debian13:nonroot

COPY --from=builder /build/server /server

USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["/server"]