#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_PATH="$(dirname "$SCRIPT_DIR")"

REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

export RCLONE_CONFIG="$USER_HOME/.config/rclone/rclone.conf"
export HOME="$USER_HOME"

CONFIG_GENERAL="$BASE_PATH/config/config_general.txt"
SYNC_PATH=$(awk -F'=' '/^SYNC_PATH=/{print $2}' "$CONFIG_GENERAL" | tr -d '\r')
SYNC_REMOTE=$(awk -F'=' '/^SYNC_REMOTE=/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')
SYNC_REMOTE="${SYNC_REMOTE:-servidor}"

HOY=$(date +%Y-%m-%d)
AYER=$(date -d "yesterday" +%Y-%m-%d)

grep -aE "^\[($HOY|$AYER)" "$BASE_PATH/log_sistema.txt" > "$BASE_PATH/log_reciente.txt"

rclone copy "$BASE_PATH/log_reciente.txt" "$SYNC_REMOTE:$SYNC_PATH/"
