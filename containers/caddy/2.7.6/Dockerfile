# FROM caddy:2.7.6-alpine

# RUN set -eux; \
# 	apkArch="$(apk --print-arch)"; \
# 	case "$apkArch" in \
# 		x86_64)  binArch='amd64' ;; \
# 		aarch64) binArch='arm64' ;; \
# 		*) echo >&2 "error: unsupported architecture ($apkArch)"; exit 1 ;;\
# 	esac; \
# 	wget -O caddy "https://github.com/igorferreir4/caddy/releases/download/v2.7.6/caddy-linux-${binArch}"; \
# 	rm /usr/bin/caddy; \
#     mv caddy /usr/bin; \
#     chmod +x /usr/bin/caddy

FROM caddy:2.7.6-builder-alpine AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/WeidiDeng/caddy-cloudflare-ip \
    --with github.com/mholt/caddy-l4 \
    --with github.com/RussellLuo/caddy-ext/layer4

FROM caddy:2.7.6-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy