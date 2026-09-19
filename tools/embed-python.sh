#!/bin/bash
set -euo pipefail
cd "$PROJECT_DIR"
python3 "$PROJECT_DIR/tools/embed_python.py"
