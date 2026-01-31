# Stage 1: Build
FROM golang:1.25-alpine AS builder

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./

RUN CGO_ENABLED=0 go build \
    -ldflags="-w -s" \
    -o registrador \
    main.go

# Stage 2: Application
FROM gcr.io/distroless/static-debian13:nonroot AS final

COPY --from=builder /build/registrador /registrador

USER nonroot:nonroot

ENTRYPOINT ["/registrador"]