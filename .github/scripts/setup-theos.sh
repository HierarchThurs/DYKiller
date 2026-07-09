#!/usr/bin/env bash

set -euo pipefail

theos_dir=${THEOS_DIR:-"${GITHUB_WORKSPACE}/theos"}
theos_src=${THEOS_SRC:-"https://github.com/roothide/theos"}
theos_sdks=${THEOS_SDKS:-"https://github.com/theos/sdks"}
theos_sdks_branch=${THEOS_SDKS_BRANCH:-"master"}

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "DYKiller CI builds require a macOS runner." >&2
    exit 1
fi

brew install ldid make p7zip

gnu_make_path="$(brew --prefix make)/libexec/gnubin"
if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "${gnu_make_path}" >> "${GITHUB_PATH}"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "THEOS=${theos_dir}" >> "${GITHUB_ENV}"
fi
export THEOS="${theos_dir}"
export PATH="${gnu_make_path}:${PATH}"

if [[ ! -d "${theos_dir}/.git" ]]; then
    rm -rf "${theos_dir}"
    git clone "${theos_src}" "${theos_dir}" --recursive
else
    git -C "${theos_dir}" submodule update --init --recursive
fi

mkdir -p "${theos_dir}/sdks"
if ! find "${theos_dir}/sdks" -maxdepth 1 -type d -name '*.sdk' | grep -q .; then
    work_dir=$(mktemp -d)
    trap 'rm -rf "${work_dir}"' EXIT

    archive="${work_dir}/sdks.zip"
    curl -L "${theos_sdks}/archive/${theos_sdks_branch}.zip" -o "${archive}"
    7z x "${archive}" "-o${work_dir}/sdks"

    find "${work_dir}/sdks" -maxdepth 2 -type d -name '*.sdk' -exec cp -R {} "${theos_dir}/sdks/" \;
fi

echo "DYKiller Theos environment is ready at ${theos_dir}."
