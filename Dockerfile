FROM --platform=$BUILDPLATFORM golang:1.25-alpine3.24 AS builder

ARG BUILDPLATFORM
ARG TARGETARCH
ARG TARGETOS
ENV GOARCH=${TARGETARCH} GOOS=${TARGETOS}

# bash + node/npm are needed to build the embedded Prometheus Mantine web UI.
RUN apk add --no-cache bash nodejs npm

COPY . /go/src/github.com/jacksontj/promxy
# Build and embed the web UI assets on the build platform, then cross-compile.
RUN /go/src/github.com/jacksontj/promxy/scripts/build_ui_assets.sh
RUN cd /go/src/github.com/jacksontj/promxy/cmd/promxy && CGO_ENABLED=0 go build -mod=vendor -tags netgo,builtinassets,embedassets
RUN cd /go/src/github.com/jacksontj/promxy/cmd/remote_write_exporter && CGO_ENABLED=0 go build -mod=vendor

FROM   alpine:3.24.1
LABEL  org.opencontainers.image.authors="Thomas Jackson <jacksontj.89@gmail.com>"
EXPOSE 8082

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /go/src/github.com/jacksontj/promxy/cmd/promxy/promxy /bin/promxy
COPY --from=builder /go/src/github.com/jacksontj/promxy/cmd/remote_write_exporter/remote_write_exporter /bin/remote_write_exporter

USER       nobody

ENTRYPOINT [ "/bin/promxy" ]

