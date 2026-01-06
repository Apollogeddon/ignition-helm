#!/usr/bin/env bash
set -eo pipefail

if [ "${IGNITION_REPLICAS}" -eq "1" ]; then
  echo "Running single replica, skipping redundancy setup."
  exit 0
fi

if [[ "${HOSTNAME}" =~ -([0-9])$ ]] && [ ! -f /data/redundancy.xml ]; then
  case "${BASH_REMATCH[1]}" in
    0)
      echo "Initializing Redundancy as Primary"
      cp /config/files/redundancy-primary.xml /data/redundancy.xml
      ;;
    1)
      echo "Initializing Redundancy as Backup"
      cp /config/files/redundancy-backup.xml /data/redundancy.xml
      ;;
    *)
      echo "Unknown Redundancy Hostname Suffix: ${HOSTNAME}"
      ;;
  esac
fi