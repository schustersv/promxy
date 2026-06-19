#!/usr/bin/env bash
#
# Build the Prometheus Mantine web UI assets and embed them into the vendored
# prometheus web/ui package, so promxy serves the query UI when built with the
# `builtinassets,embedassets` tags (see Makefile / build.bash).
#
# Why this exists: `go mod vendor` strips the React/Mantine sources from
# vendor/ (it keeps only Go files), so the UI cannot be built from the vendor
# tree. Instead we build from the prometheus module source in the module cache
# and copy the compressed, embeddable output back into vendor. This mirrors
# prometheus' own `make assets assets-compress`, reduced to just the Mantine UI
# that promxy actually serves.
#
# The generated embed.go and static/*.gz files are gitignored (see
# vendor/.../web/ui/.gitignore): they are build artifacts, regenerated on every
# release rather than committed. The committed embed_stub.go provides an empty
# fallback under the mutually exclusive `builtinassets && !embedassets` tag so
# that `go test -tags builtinassets ./...` keeps compiling without building the
# UI.
#
# Set FORCE=1 to rebuild even if assets are already present.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO_ROOT="$(pwd)"

PROM_MODULE="github.com/prometheus/prometheus"
VENDOR_UI="vendor/${PROM_MODULE}/web/ui"

if [[ -z "${FORCE:-}" && -f "${VENDOR_UI}/embed.go" ]]; then
  echo ">> UI assets already present (${VENDOR_UI}/embed.go); set FORCE=1 to rebuild"
  exit 0
fi

command -v npm >/dev/null 2>&1 || {
  echo "error: npm is required to build the web UI (need node >= 22, npm >= 10)" >&2
  exit 1
}

# Resolve the exact prometheus module source promxy builds against, honoring any
# replace directive in go.mod.
modref="$(go list -m -mod=mod -f '{{with .Replace}}{{.Path}}@{{.Version}}{{else}}{{.Path}}@{{.Version}}{{end}}' "${PROM_MODULE}")"
echo ">> building UI assets from ${modref}"

go mod download "${modref}"
mod_dir="$(go mod download -json "${modref}" | sed -n 's/^[[:space:]]*"Dir": "\(.*\)",\{0,1\}$/\1/p')"
if [[ -z "${mod_dir}" || ! -d "${mod_dir}/web/ui" ]]; then
  echo "error: could not locate web/ui sources for ${modref}" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
cp -r "${mod_dir}/web/ui" "${work_dir}/ui"
chmod -R u+w "${work_dir}"

pushd "${work_dir}/ui" >/dev/null

echo ">> npm install"
npm install

echo ">> building shared modules"
npm run build:module

echo ">> building mantine-ui"
CI="" npm run build -w @prometheus-io/mantine-ui
mkdir -p static
rm -rf static/mantine-ui
mv mantine-ui/dist static/mantine-ui

echo ">> compressing assets and generating embed.go"
# Mirrors prometheus' scripts/compress_assets.sh.
cp embed.go.tmpl embed.go
gzip_opts="-fkn"
# '-k' may not exist on older gzip builds.
gzip -k -h >/dev/null 2>&1 || gzip_opts="-fn"
find static -type f -name '*.gz' -delete
find static -type f ! -name '*.gz' -exec bash -c '
  for file; do
    dest="${file#static}"
    mkdir -p "static/$(dirname "$dest")"
    gzip '"${gzip_opts}"' "$file" -c > "static/${dest}.gz"
  done
' bash {} +
find static -type f -name '*.gz' -print0 | sort -z | xargs -0 echo //go:embed >> embed.go
echo "var EmbedFS embed.FS" >> embed.go
# Constrain the generated bundle to the `embedassets` tag so it is mutually
# exclusive with the committed embed_stub.go fallback.
sed -i \
  -e 's#^//go:build builtinassets$#//go:build builtinassets \&\& embedassets#' \
  -e 's#^// +build builtinassets$#// +build builtinassets,embedassets#' \
  embed.go

popd >/dev/null

echo ">> installing assets into ${VENDOR_UI}"
rm -rf "${VENDOR_UI}/static" "${VENDOR_UI}/embed.go"
mkdir -p "${VENDOR_UI}"
cp "${work_dir}/ui/embed.go" "${VENDOR_UI}/embed.go"
(
  cd "${work_dir}/ui"
  find static -name '*.gz' | while read -r f; do
    mkdir -p "${REPO_ROOT}/${VENDOR_UI}/$(dirname "$f")"
    cp "$f" "${REPO_ROOT}/${VENDOR_UI}/$f"
  done
)

echo ">> done"
