//go:build builtinassets && embedassets

// This file is only compiled when promxy is built with the real embedded web
// UI assets (-tags builtinassets,embedassets). The default `make test` build
// uses the empty embed_stub.go fallback and intentionally excludes this test;
// run it via `make test-ui`, which builds the assets first.

package test

import (
	"io"
	"strings"
	"testing"

	"github.com/prometheus/prometheus/web/ui"
)

// TestWebUIIndexEmbedded guards against the regression where the Mantine web UI
// was not built/embedded, so promxy's /query endpoint returned
// "Error opening React index.html: open static/mantine-ui/index.html.gz: file
// does not exist". It checks the same asset, via the same FileSystem, that
// web.go's serveReactApp serves (reactAssetsRoot + "/index.html").
func TestWebUIIndexEmbedded(t *testing.T) {
	f, err := ui.Assets.Open("/static/mantine-ui/index.html")
	if err != nil {
		t.Fatalf("Mantine UI index.html is not embedded; the web UI assets were not built. "+
			"Run `make assets` (or `make test-ui`). underlying error: %v", err)
	}
	defer f.Close()

	b, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("reading embedded index.html: %v", err)
	}
	if len(b) == 0 {
		t.Fatal("embedded index.html is empty")
	}

	// The React app mounts into this element; its presence confirms the embedded
	// file is the real application shell rather than a placeholder/stub.
	if !strings.Contains(string(b), `<div id="root">`) {
		t.Fatalf("embedded index.html does not look like the Mantine app shell (missing root mount point); got %d bytes", len(b))
	}
}
