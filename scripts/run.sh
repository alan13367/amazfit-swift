#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh "${1:-debug}"
open .build/Helio.app
