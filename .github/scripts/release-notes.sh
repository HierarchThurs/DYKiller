#!/usr/bin/env bash

set -euo pipefail

notes_file=${1:-release-notes.md}
version=$(awk -F': *' '$1 == "Version" { print $2; exit }' control)
release_sha=${RELEASE_SHA:-${GITHUB_SHA:-HEAD}}

if [[ -z "${version}" ]]; then
    echo "Unable to read Version from control." >&2
    exit 1
fi

cat > "${notes_file}" <<NOTES
## DYKiller ${version}

- Commit: \`${release_sha}\`
- Rootful: \`DYKiller_${version}_arm-rootful.deb\`
- Rootless: \`DYKiller_${version}_arm64-rootless.deb\`
- Roothide: \`DYKiller_${version}_arm64e-roothide.deb\`
- Dylib: \`DYKiller.dylib\`
NOTES
