#!/bin/bash

set -e

TEMPLATE_FILE="/app/template_config.yaml"
CONFIG_DIR="/config"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

cp -f "$TEMPLATE_FILE" "$CONFIG_FILE"
