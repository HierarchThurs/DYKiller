#!/usr/bin/env bash

set -euo pipefail

rm -rf packages
mkdir -p packages

make package-rootful FINALPACKAGE=1
make package-rootless FINALPACKAGE=1
make package-roothide FINALPACKAGE=1
