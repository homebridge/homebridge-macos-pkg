FROM alpine:3.19
LABEL maintainer="homebridge <noreply@homebridge.local>"

# Minimal container to prepare staging tree for macOS package
RUN apk add --no-cache ca-certificates curl tar xz jq python3 bash

WORKDIR /work

COPY .. /work/src
WORKDIR /work/src

ENTRYPOINT ["/bin/bash", "-lc"]
