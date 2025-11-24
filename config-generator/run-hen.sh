#!/bin/bash
cd /opt/clash-proxy-rules-gen/config-generator
./.venv/bin/python sync_configs.py

# Make this file executable with: chmod +x run-gen.sh
# You can run it with: ./run-gen.sh