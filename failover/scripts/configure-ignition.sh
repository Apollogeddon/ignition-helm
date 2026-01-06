#!/usr/bin/env bash
set -eo pipefail

echo "Running configure-ignition.sh"

# Gateway Restore Configuration
if [ -n "$IGNITION_RESTORE_URL" ]; then
    echo "Downloading Gateway Backup from $IGNITION_RESTORE_URL..."
    if command -v curl &> /dev/null; then
        curl -L -o /data/restore.gwbk "$IGNITION_RESTORE_URL"
        echo "Gateway Backup downloaded to /data/restore.gwbk"
    elif command -v wget &> /dev/null; then
        wget -O /data/restore.gwbk "$IGNITION_RESTORE_URL"
        echo "Gateway Backup downloaded to /data/restore.gwbk"
    else
        echo "Error: Neither curl nor wget found. Cannot download Gateway Backup."
        exit 1
    fi
elif [ -n "$IGNITION_RESTORE_PATH" ]; then
    echo "Copying Gateway Backup from $IGNITION_RESTORE_PATH..."
    if [ -f "$IGNITION_RESTORE_PATH" ]; then
        cp "$IGNITION_RESTORE_PATH" /data/restore.gwbk
        echo "Gateway Backup copied to /data/restore.gwbk"
    else
        echo "Error: File not found at $IGNITION_RESTORE_PATH"
        exit 1
    fi
else
    echo "No Ignition Restore URL or Path provided. Skipping Gateway Backup restore."
fi

echo "configure-ignition.sh finished."