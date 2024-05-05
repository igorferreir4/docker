### This is a fork from https://hub.docker.com/r/marioezquerro/registrator with arm64 support

## Github Repository

- [CLICK](https://github.com/igorferreir4/docker/tree/main/containers)

## CLI Options
```
Usage of /bin/registrator:
  /bin/registrator [options] <registry URI>

  -cleanup=false: Remove dangling services
  -deregister="always": Deregister exited services "always" or "on-success"
  -internal=false: Use internal ports instead of published ones
  -ip="": IP for ports mapped to the host
  -resync=0: Frequency with which services are resynchronized
  -retry-attempts=0: Max retry attempts to establish a connection with the backend. Use -1 for infinite retries
  -retry-interval=2000: Interval (in millisecond) between retry-attempts.
  -tags="": Append tags for all registered services
  -ttl=0: TTL for services (default is no expiry)
  -ttl-refresh=0: Frequency with which service TTLs are refreshed
```

## Example Docker Compose
```
  registrator:
    image: igorferreir4/registrator:latest
    container_name: consul-registrator
    restart: always
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
    command: -cleanup -deregister always -resync 10 -tags "example-tag" -ip <ip-to-register> consul://<consul-ip-or-hostname>:8500
    network_mode: host
```