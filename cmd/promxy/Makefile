test-demo:
	../../scripts/build_ui_assets.sh && go build -race -mod=vendor -tags netgo,builtinassets,embedassets && ./promxy --rules.alertbackfill --log-level=debug --http.shutdown-delay=0s --config=demo.conf --web.external-url=http://localhost:8082/promxy


test-local:
	../../scripts/build_ui_assets.sh && go build -race -mod=vendor -tags netgo,builtinassets,embedassets && ./promxy --http.shutdown-delay=0s --config=local_test.conf --web.external-url=http://localhost:8082/promxy --log-level=debug

version:
	go build -race -mod=vendor -tags netgo,builtinassets && ./promxy --version
