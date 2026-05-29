#!/usr/bin/env bash
set -euo pipefail

: "${RPM_GPG_NAME:?Set RPM_GPG_NAME to the GPG key identity used for repo signing}"

GNUPGHOME="${GNUPGHOME:-$PWD/build/gnupg-sign}"
REPO_DIR="${REPO_DIR:-dist/repo/el7/x86_64}"
PUBLIC_KEY_OUT="${RPM_GPG_PUBLIC_KEY_OUT:-dist/RPM-GPG-KEY-rosa-khutor}"
REPOMD="$REPO_DIR/repodata/repomd.xml"

mkdir -p "$GNUPGHOME" dist
chmod 700 "$GNUPGHOME"

if [[ -n "${RPM_GPG_PRIVATE_KEY_B64:-}" ]]; then
  printf '%s' "$RPM_GPG_PRIVATE_KEY_B64" | base64 -d | \
    GNUPGHOME="$GNUPGHOME" gpg --batch --import
elif [[ -n "${RPM_GPG_PRIVATE_KEY_FILE:-}" ]]; then
  GNUPGHOME="$GNUPGHOME" gpg --batch --import "$RPM_GPG_PRIVATE_KEY_FILE"
elif ! GNUPGHOME="$GNUPGHOME" gpg --batch --list-secret-keys "$RPM_GPG_NAME" >/dev/null 2>&1; then
  echo "No private key found for RPM_GPG_NAME=$RPM_GPG_NAME" >&2
  echo "Provide RPM_GPG_PRIVATE_KEY_B64, RPM_GPG_PRIVATE_KEY_FILE, or pre-import it into GNUPGHOME." >&2
  exit 1
fi

if [[ ! -f "$REPOMD" ]]; then
  echo "Repo metadata not found: $REPOMD" >&2
  exit 1
fi

GNUPGHOME="$GNUPGHOME" gpg --batch --yes --armor --detach-sign \
  --local-user "$RPM_GPG_NAME" \
  "$REPOMD"

GNUPGHOME="$GNUPGHOME" gpg --batch --armor --export "$RPM_GPG_NAME" > "$PUBLIC_KEY_OUT"

echo "Repo metadata signature: $PWD/$REPOMD.asc"
echo "RPM public key: $PWD/$PUBLIC_KEY_OUT"
