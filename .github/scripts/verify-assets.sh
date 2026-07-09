#!/usr/bin/env bash

set -euo pipefail

version=$(awk -F': *' '$1 == "Version" { print $2; exit }' control)
if [[ -z "${version}" ]]; then
    echo "Unable to read Version from control." >&2
    exit 1
fi

expected_assets=(
    "packages/DYKiller_${version}_arm-rootful.deb"
    "packages/DYKiller_${version}_arm64-rootless.deb"
    "packages/DYKiller_${version}_arm64e-roothide.deb"
    "packages/DYKiller.dylib"
)

for asset in "${expected_assets[@]}"; do
    if [[ ! -f "${asset}" ]]; then
        echo "Missing expected asset: ${asset}" >&2
        find packages -maxdepth 1 -type f -print 2>/dev/null | sort >&2
        exit 1
    fi
done

deb_count=$(find packages -maxdepth 1 -type f -name '*.deb' | wc -l | tr -d ' ')
dylib_count=$(find packages -maxdepth 1 -type f -name '*.dylib' | wc -l | tr -d ' ')
if [[ "${deb_count}" != "3" || "${dylib_count}" != "1" ]]; then
    echo "Expected 3 deb files and 1 dylib, found ${deb_count} deb and ${dylib_count} dylib." >&2
    find packages -maxdepth 1 -type f -print | sort >&2
    exit 1
fi

printf 'Verified asset: %s\n' "${expected_assets[@]}"
