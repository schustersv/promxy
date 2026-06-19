BUILD := build
GO ?= go
GOFILES := $(shell find . -name "*.go" -type f ! -path "./vendor/*")
GOFMT ?= gofmt
GOIMPORTS ?= goimports -local=github.com/jacksontj/promxy
STATICCHECK ?= staticcheck
VENDOR_PROM_UI := vendor/github.com/prometheus/prometheus/web/ui

.PHONY: clean
clean:
	$(GO) clean -i ./...
	rm -rf $(BUILD)
	rm -rf $(VENDOR_PROM_UI)/static $(VENDOR_PROM_UI)/embed.go

# Build the Prometheus Mantine web UI and embed it into the vendored prometheus
# web/ui package. The generated embed.go and static/*.gz files are gitignored
# build artifacts; they are regenerated here rather than committed. Set FORCE=1
# to rebuild even if they already exist.
.PHONY: assets
assets:
	./scripts/build_ui_assets.sh

.PHONY: static-check
static-check:
	$(STATICCHECK) ./...

.PHONY: fmt
fmt:
	$(GOFMT) -w -s $(GOFILES)

.PHONY: imports
imports:
	$(GOIMPORTS) -w $(GOFILES)

.PHONY: test
test:
	GO111MODULE=on $(GO) test -race -mod=vendor -tags netgo,builtinassets ./...

# Verifies the Mantine web UI is built and embedded. Runs only under the
# embedassets tag and builds the assets first (via the `assets` dependency); the
# default `make test` uses the empty embed_stub.go fallback and skips this test.
.PHONY: test-ui
test-ui: assets
	GO111MODULE=on $(GO) test -mod=vendor -tags netgo,builtinassets,embedassets ./test/ -run TestWebUI -v

.PHONY: release
release: assets
	./build.bash github.com/jacksontj/promxy/cmd/promxy $(BUILD)
	./build.bash github.com/jacksontj/promxy/cmd/remote_write_exporter $(BUILD)

testlocal-build:
	docker build -t 127.0.0.1:32000/promxy:latest .
	docker push 127.0.0.1:32000/promxy:latest

.PHONY: vendor
vendor:
	GO111MODULE=on $(GO) mod tidy -compat=1.20
	GO111MODULE=on $(GO) mod vendor

.PHONY: update-prom-fork
update-prom-fork:
	GO111MODULE=on $(GO) mod edit -replace github.com/prometheus/prometheus=github.com/jacksontj/prometheus@v0.2.37.5-fork
	$(MAKE) vendor
