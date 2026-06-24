#!/bin/bash
set -euo pipefail

echo "Running push-ready backend regression tests..."
python -m pytest \
  tests/test_harness_runtime.py \
  tests/test_agent_verifier.py \
  tests/test_query_frame_display_specs.py \
  tests/test_product_reference_resolution.py \
  tests/test_api_contract_runtime.py \
  tests/test_harness_preflight.py \
  tests/test_harness_postflight.py \
  tests/agent \
  tests/verification/test_config_loader.py \
  tests/test_unit.py \
  -q

echo
echo "Running frontend production build..."
(
  cd frontend
  npm run build
)
