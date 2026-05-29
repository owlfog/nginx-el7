#!/usr/bin/env bash
set -euo pipefail

NGINX_VERSION="${NGINX_VERSION:-1.30.2}"
NGINX_RELEASE="${NGINX_RELEASE:-1}"
DIST="${DIST:-.el7}"
RPM_TOPDIR="${RPM_TOPDIR:-$PWD/build/rpmbuild}"
SOURCE_DIR="$RPM_TOPDIR/SOURCES"
SPEC_DIR="$RPM_TOPDIR/SPECS"
TARBALL="$SOURCE_DIR/nginx-$NGINX_VERSION.tar.gz"
VERIFY_PGP="${NGINX_VERIFY_PGP:-1}"

mkdir -p "$RPM_TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} dist/rpms dist/srpms

if [[ ! -f "$TARBALL" ]]; then
  curl -fL --retry 3 --retry-delay 2 \
    -o "$TARBALL.tmp" \
    "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"
  mv "$TARBALL.tmp" "$TARBALL"
fi

if [[ -n "${NGINX_SHA256:-}" ]]; then
  echo "$NGINX_SHA256  $TARBALL" | sha256sum -c -
else
  sha256sum "$TARBALL" | tee "dist/nginx-$NGINX_VERSION.tar.gz.sha256"
fi

if [[ "$VERIFY_PGP" == "1" ]]; then
  ASC_FILE="$TARBALL.asc"
  GNUPGHOME_DIR="$RPM_TOPDIR/gnupg"
  KEY_URLS=(
    "https://nginx.org/keys/nginx_signing.key"
    "https://nginx.org/keys/arut.key"
    "https://nginx.org/keys/pluknet.key"
    "https://nginx.org/keys/sb.key"
    "https://nginx.org/keys/thresh.key"
  )

  if [[ ! -f "$ASC_FILE" ]]; then
    curl -fL --retry 3 --retry-delay 2 \
      -o "$ASC_FILE.tmp" \
      "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc"
    mv "$ASC_FILE.tmp" "$ASC_FILE"
  fi

  mkdir -p "$GNUPGHOME_DIR"
  chmod 700 "$GNUPGHOME_DIR"

  for key_url in "${KEY_URLS[@]}"; do
    key_file="$SOURCE_DIR/$(basename "$key_url")"
    if [[ ! -f "$key_file" ]]; then
      curl -fL --retry 3 --retry-delay 2 -o "$key_file.tmp" "$key_url"
      mv "$key_file.tmp" "$key_file"
    fi
    GNUPGHOME="$GNUPGHOME_DIR" gpg --batch --import "$key_file"
  done

  GNUPGHOME="$GNUPGHOME_DIR" gpg --batch --verify "$ASC_FILE" "$TARBALL"
fi

cp packaging/SOURCES/* "$SOURCE_DIR/"
sed \
  -e "s/@NGINX_VERSION@/$NGINX_VERSION/g" \
  -e "s/@NGINX_RELEASE@/$NGINX_RELEASE/g" \
  packaging/SPECS/nginx.spec.in > "$SPEC_DIR/nginx.spec"

rpmbuild \
  --define "_topdir $RPM_TOPDIR" \
  --define "dist $DIST" \
  -ba "$SPEC_DIR/nginx.spec"

find "$RPM_TOPDIR/RPMS" -type f -name '*.rpm' -exec cp -f {} dist/rpms/ \;
find "$RPM_TOPDIR/SRPMS" -type f -name '*.rpm' -exec cp -f {} dist/srpms/ \;

rpm -qpi dist/rpms/nginx-"$NGINX_VERSION"-"$NGINX_RELEASE""$DIST".rhcustom.*.rpm
