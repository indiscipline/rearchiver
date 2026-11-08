#!/usr/bin/env bash
set -euo pipefail

tag="${1:?usage: $0 <tag> [owner/repo]}"
repo="${2:-indiscipline/rearchiver}"

if [[ "$tag" != v* ]]; then
  echo "error: release tag must start with 'v': $tag" >&2
  exit 2
fi

pkgver="${tag#v}"
base="https://github.com/${repo}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 -o "${tmp}/rearchiver_linux" \
  "${base}/releases/download/${tag}/rearchiver_linux"
curl -fsSL --retry 3 -o "${tmp}/LICENSE.md" \
  "${base}/raw/${tag}/LICENSE.md"

bin_sha="$(sha256sum "${tmp}/rearchiver_linux" | cut -d' ' -f1)"
license_sha="$(sha256sum "${tmp}/LICENSE.md" | cut -d' ' -f1)"

cat >PKGBUILD <<EOF
# Maintainer: Kirill I <elephanttalk+aur@protonmail.com>

pkgname=rearchiver-bin
pkgver=${pkgver}
pkgrel=1
pkgdesc='Prepare Reaper projects for archiving by converting WAV to FLAC/WavPack'
arch=('x86_64')
url='https://github.com/indiscipline/rearchiver'
license=('GPL-3.0-or-later')
depends=('glibc' 'flac')
optdepends=('wavpack: 32/64-bit floating point support')
provides=('rearchiver')
conflicts=('rearchiver')
options=('!strip')
source=(
  "rearchiver-\${pkgver}::${base}/releases/download/${tag}/rearchiver_linux"
  "LICENSE-\${pkgver}::${base}/raw/${tag}/LICENSE.md"
)
sha256sums=('${bin_sha}' '${license_sha}')

package() {
  install -Dm755 "\${srcdir}/rearchiver-\${pkgver}" \
    "\${pkgdir}/usr/bin/rearchiver"
  install -Dm644 "\${srcdir}/LICENSE-\${pkgver}" \
    "\${pkgdir}/usr/share/licenses/\${pkgname}/LICENSE.md"
}
EOF

if command -v makepkg >/dev/null 2>&1; then
  makepkg --printsrcinfo >.SRCINFO
fi
