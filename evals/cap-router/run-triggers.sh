#!/usr/bin/env bash
# Trigger & collision tier: TF-IDF routing approximation over skill descriptions.
#   ./run-triggers.sh                         # live ~/.agents/skills
#   ./run-triggers.sh --compare triggers-baseline.json
#   ./run-triggers.sh --skills-dir <snapshot> --save out.json
set -euo pipefail
exec /usr/bin/python3 -I "$(cd "$(dirname "$0")" && pwd)/triggers.py" "$@"
