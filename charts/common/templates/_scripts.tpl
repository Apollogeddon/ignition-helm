{{- define "ignition-common.scripts" -}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "ignition-common.scriptsName" . }}
  labels:
    {{- include "ignition-common.labels" . | nindent 4 }}
stringData:
  seed-data-volume.sh: |-
    #!/usr/bin/env bash
    set -eo pipefail

    if [ ! -f /data/.ignition-seed-complete ]; then
        echo "Seeding Ignition Data Volume"
        touch /data/.ignition-seed-complete
        cp -dpR /usr/local/bin/ignition/data/* /data/
    fi
  seed-redundancy.sh: |-
    #!/usr/bin/env bash
    # Applies the chart's redundancy settings to the gateway's data volume on
    # every start, so redundancy values - including turning redundancy on or
    # off - take effect on existing installs, not only on the first start:
    #   - pair, no redundancy.xml yet: seed it from the chart's template
    #     (pod 0 Master, pod 1 Backup)
    #   - pair, redundancy.xml exists: set every key the chart renders to the
    #     chart's value (role, peer address, timeouts, recovery mode, ...)
    #   - single replica with a redundancy.xml left from a pair: set the role
    #     to Independent
    #   - single replica that was never redundant: nothing
    # Ignition's own sync state (systemstateuid, systemstaterevision) and keys
    # the chart does not render are never changed.
    set -eo pipefail
    DATA_DIR="${DATA_DIR:-/data}"
    FILES_DIR="${FILES_DIR:-/config/files}"
    file="${DATA_DIR}/redundancy.xml"
    runtime_keys=" redundancy.systemstateuid redundancy.systemstaterevision "

    # value <entry line>: the value of an <entry key="...">value</entry> line
    value() {
      if [ -n "$1" ]; then printf '%s' "$1" | sed 's/.*">\(.*\)<\/entry>.*/\1/'; else printf '(unset)'; fi
    }

    # set_entry <key> <entry line>: make the key's line in redundancy.xml match,
    # replacing it or adding it before </properties>
    set_entry() {
      local key="$1" want="$2" have esc key_re
      have=$(grep -F "key=\"${key}\"" "${file}" | tr -d '\r' || true)
      [ "${have}" = "${want}" ] && return 0
      echo "Updating ${key}: $(value "${have}") -> $(value "${want}")"
      esc=$(printf '%s' "${want}" | sed 's/[&|\]/\&/g')
      key_re=$(printf '%s' "${key}" | sed 's/[.]/\./g')
      if [ -n "${have}" ]; then
        sed -i "s|^.*key=\"${key_re}\".*\$|${esc}|" "${file}"
      else
        sed -i "s|</properties>|${esc}\n</properties>|" "${file}"
      fi
    }

    if [ "${IGNITION_REPLICAS:-1}" -eq 1 ]; then
      if [ -f "${file}" ]; then
        set_entry redundancy.noderole '<entry key="redundancy.noderole">Independent</entry>'
      else
        echo "Single replica, no redundancy settings to apply."
      fi
      exit 0
    fi

    if ! [[ "${HOSTNAME}" =~ -([0-9]+)$ ]]; then
      echo "Unknown Redundancy Hostname Suffix: ${HOSTNAME}"
      exit 0
    fi
    case "${BASH_REMATCH[1]}" in
      0) role=Master; template="${FILES_DIR}/redundancy-primary.xml" ;;
      1) role=Backup; template="${FILES_DIR}/redundancy-backup.xml" ;;
      *) echo "Unknown Redundancy Hostname Suffix: ${HOSTNAME}"; exit 0 ;;
    esac

    if [ ! -f "${file}" ]; then
      echo "Initializing Redundancy as ${role}"
      tr -d '\r' < "${template}" > "${file}"
      exit 0
    fi

    while IFS= read -r line; do
      line="${line%$'\r'}"
      [[ "${line}" =~ key=\"([^\"]+)\" ]] || continue
      key="${BASH_REMATCH[1]}"
      case "${runtime_keys}" in *" ${key} "*) continue ;; esac
      set_entry "${key}" "${line}"
    done < "${template}"
  prepare-gan-certificates.sh: |-
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Preparing Gateway Network Certificates"

    # Global variable defaults
    IGNITION_DATA_DIR="/data"
    GAN_CA_SECRETS_DIR="/run/secrets/ignition-gan-ca"
    GAN_SECRETS_DIR="/run/secrets/gan-tls"
    METRO_KEYSTORE_ALIAS="metro-key"
    GWBK_LOCATION=""

    ###############################################################################
    # Places GAN CA Certificate and GAN Client Keystores into place
    ###############################################################################
    function main() {
      # Populate GAN CA Certificate into the trusted certs folder
      populateGanCaCertificate

      # Update the alias in the inbound GAN PKCS#12 keystore and place into `data/local`
      populateGanKeystore

      # Update the GWBK with the GAN CA Certificate trust
      if [ -n "${GWBK_LOCATION:-}" ]; then
        updateGwbk
      fi
    }

    ###############################################################################
    # Places the GAN Client Keystore into the Ignition data/local folder
    ###############################################################################
    function populateGanKeystore() {
      info "Populating GAN Client Keystore into Ignition data/local/metro-keystore"

      # Ensure the destination directory exists
      mkdir -v -p "${IGNITION_DATA_DIR}/local"

      # Replace any existing GAN client keystore with the updated one from the mounted secret
      rm -v -f "${IGNITION_DATA_DIR}/local/metro-keystore"
      cp "${GAN_SECRETS_DIR}/keystore.p12" "${IGNITION_DATA_DIR}/local/metro-keystore"

      # Modify the GAN client keystore to use the alias "metro-key" to align with Ignition defaults
      existing_alias=$(keytool -list -keystore "${IGNITION_DATA_DIR}/local/metro-keystore" -storepass ${METRO_KEYSTORE_PASSPHRASE} | grep PrivateKeyEntry | cut -d, -f 1)
      target_alias="${METRO_KEYSTORE_ALIAS}"
      if [ "${existing_alias}" != "${target_alias}" ]; then
        keytool -changealias -alias "${existing_alias}" -destalias "${target_alias}" \
          -keystore "${IGNITION_DATA_DIR}/local/metro-keystore" -storepass ${METRO_KEYSTORE_PASSPHRASE}
      fi
    }

    ###############################################################################
    # Places the GAN CA Certificate into the Ignition gateway network trusted certs
    ###############################################################################
    function populateGanCaCertificate() {
      info "Populating GAN CA Certificate into Ignition gateway network trusted certs folders"

      # Copy the GAN Issuer CA certificate to trusted certs for server/client to establish root trust
      mkdir -v -p "${IGNITION_DATA_DIR}/gateway-network/server/security/pki/trusted/certs/"
      mkdir -v -p "${IGNITION_DATA_DIR}/gateway-network/client/security/pki/trusted/certs/"
      cp -v "${GAN_CA_SECRETS_DIR}/ca.crt" "${IGNITION_DATA_DIR}/gateway-network/server/security/pki/trusted/certs/ignition-gan-ca.crt"
      cp -v "${GAN_CA_SECRETS_DIR}/ca.crt" "${IGNITION_DATA_DIR}/gateway-network/client/security/pki/trusted/certs/ignition-gan-ca.crt"
    }

    ###############################################################################
    # Updates the GWBK with the GAN CA Certificate trust
    ###############################################################################
    function updateGwbk() {
      info "Updating GWBK with GAN CA Certificate trust"

      if ! command -v zip &> /dev/null || ! command -v zipnote &> /dev/null; then
        >&2 echo "WARNING: 'zip' or 'zipnote' command not found. Skipping GAN CA trust injection into GWBK."
        >&2 echo "Ensure your Ignition image includes zip utilities for this feature."
        return 0
      fi

      # Target destination paths for the GAN CA certificate
      local dest_locations=(
        "gateway-network/server/security/pki/trusted/certs/ignition-gan-ca.crt"
        "gateway-network/client/security/pki/trusted/certs/ignition-gan-ca.crt"
      )

      # Remove existing files in destination location (if present)
      zip -d "${GWBK_LOCATION}" "${dest_locations[@]}" || true
      
      # Add the GAN CA Certificate to the GWBK in client/server folders
      for dest in "${dest_locations[@]}"; do
        zip -j "${GWBK_LOCATION}" "${GAN_CA_SECRETS_DIR}/ca.crt" "${dest}"
        printf "@ ca.crt\n@=%s\n" "${dest}" | zipnote -w "${GWBK_LOCATION}"
      done

      debug "Zip contents:\n$(unzip -l "${GWBK_LOCATION}")"
    }

    ###############################################################################
    # Alias for printing to console/stdout
    # Arguments:
    #   <...> Content to print
    ###############################################################################
    function info() {
      readarray -t message_arr <<< "${*}"
      for message_line in "${message_arr[@]}"; do
        printf "%s\n" "${message_line}"
      done
    }

    ###############################################################################
    # Outputs to stderr
    ###############################################################################
    function debug() {
      # shellcheck disable=SC2236
      if [ ! -z ${verbose+x} ]; then
        >&2 echo "  DEBUG: $*"
      fi
    }

    ###############################################################################
    # Print usage information
    ###############################################################################
    function usage() {
      >&2 echo "Usage: $0 -a <alias> -c <path/to/ca/secret> -s <path/to/gan/secret> -d <path/to/data/folder> [-g <path/to/gwbk>]"
      >&2 echo "  -a <alias> - The alias to use for the GAN client keystore (default: ${METRO_KEYSTORE_ALIAS})"
      >&2 echo "  -c <path/to/ca/secret> - The path to the mounted secret containing the GAN CA certificate (default: ${GAN_CA_SECRETS_DIR})"
      >&2 echo "  -s <path/to/gan/secret> - The path to the mounted secret containing the GAN client certs/keystore (default: ${GAN_SECRETS_DIR})"
      >&2 echo "  -d <path/to/data/folder> - The path to the Ignition data folder (default: ${IGNITION_DATA_DIR})"
      >&2 echo "  -g <path/to/gwbk> - Supply a GWBK to attempt to update with GAN CA trust"
      >&2 echo "  -h - Print this help message"
      >&2 echo "  -v - Enable verbose output"
    }

    # Argument Processing
    while getopts ":hva:c:s:d:g:" opt; do
      case "$opt" in
      v) 
        verbose=1
        ;;
      a) 
        METRO_KEYSTORE_ALIAS="${OPTARG}"
        ;;
      c) 
        GAN_CA_SECRETS_DIR="${OPTARG}"
        ;;
      s) 
        GAN_SECRETS_DIR="${OPTARG}"
        ;;
      d) 
        IGNITION_DATA_DIR="${OPTARG}"
        ;;
      g)
        GWBK_LOCATION="${OPTARG}"
      ;;
      h) 
        usage
        exit 0
        ;;
      \?)
        usage
        echo "Invalid option: -${OPTARG}" >&2
        exit 1
        ;;
      :)
        usage
        echo "Invalid option: -${OPTARG} requires an argument" >&2
        exit 1
        ;;
      esac
    done

    # shift positional args based on number consumed by getopts
    shift $((OPTIND-1))

    # Perform argument checks
    if [ ! -f "${GAN_CA_SECRETS_DIR}/ca.crt" ]; then
      >&2 echo "ERROR: GAN CA Certificate not found at ${GAN_CA_SECRETS_DIR}/ca.crt"
      usage
      exit 1
    fi

    if [ ! -f "${GAN_SECRETS_DIR}/keystore.p12" ]; then
      >&2 echo "ERROR: GAN Client Keystore not found at ${GAN_SECRETS_DIR}/keystore.p12"
      usage
      exit 1
    fi

    if [ ! -d "${IGNITION_DATA_DIR}" ]; then
      >&2 echo "ERROR: Ignition Data Directory not found at ${IGNITION_DATA_DIR}"
      usage
      exit 1
    fi

    if [ -n "${GWBK_LOCATION:-}" ] && [ ! -f "${GWBK_LOCATION}" ]; then
      >&2 echo "ERROR: GWBK not found at ${GWBK_LOCATION}"
      usage
      exit 1
    fi

    # check if zip and zipnote commands are installed and exit if gwbk is supplied
    if [ -n "${GWBK_LOCATION:-}" ]; then
      if ! command -v zip &> /dev/null; then
        >&2 echo "ERROR: GWBK specified, but 'zip' command not found"
        exit 1
      fi
      if ! command -v zipnote &> /dev/null; then
        >&2 echo "ERROR: GWBK specified, but 'zipnote' command not found"
        exit 1
      fi
    fi

    main
  prepare-tls-certificates.sh: |-
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Preparing Web Server TLS Certificates"

    # Replace any existing TLS keystore with the updated one from the mounted secret
    rm -v -f /data/local/ssl.pfx
    cp /run/secrets/web-tls/keystore.p12 /data/local/ssl.pfx

    # Modify the TLS keystore to use the alias "ignition" to align with Ignition defaults
    existing_alias=$(keytool -list -keystore /data/local/ssl.pfx -storepass "${TLS_KEYSTORE_PASSWORD}" | grep PrivateKeyEntry | cut -d, -f 1)
    target_alias="ignition"
    if [ "${existing_alias}" != "${target_alias}" ]; then
      keytool -changealias -alias "${existing_alias}" -destalias ${target_alias} \
        -keystore /data/local/ssl.pfx -storepass "${TLS_KEYSTORE_PASSWORD}"
    fi
  invoke-args.sh: |-
    #!/usr/bin/env bash
    set -eo pipefail

    # Helper script to simply invoke args passed on the CLI
    for arg in "$@"; do
      eval "$arg"
    done
  configure-ignition.sh: |-
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
  active-routing.sh: |-
    #!/bin/sh
    # Keeps ACTIVE_LABEL=true on the gateway pod that is currently serving, so
    # the <name>-active Service only reaches that pod. Readiness can't do this:
    # a cold Backup must count as Ready or StatefulSet rolling updates stall.
    #
    # Every INTERVAL_SECONDS each gateway pod is classified from /system/gwinfo:
    #   active   - ContextStatus=RUNNING and RedundantNodeActiveStatus=Active (or
    #              no redundancy fields at all, i.e. standalone)
    #   inactive - answered but not RUNNING/Active, has no IP yet, or is terminating
    #   unknown  - didn't answer
    # The label goes to the active Master, else any active node (a Backup that
    # took over), so during a failback overlap traffic stays on one gateway.
    # Explicit states switch immediately; if the labelled pod is merely unknown,
    # the label is held for up to UNKNOWN_HOLD polls so one slow request doesn't
    # drop traffic.
    set -u

    namespace="${NAMESPACE}"
    selector="${POD_SELECTOR}"
    label="${ACTIVE_LABEL}"
    port="${HTTP_PORT:-8088}"
    interval="${INTERVAL_SECONDS:-2}"
    unknown_hold="${UNKNOWN_HOLD:-3}"
    max_loops="${MAX_LOOPS:-0}" # 0 = forever (non-zero only for tests)

    log() {
      printf '[active] %s\n' "$*"
    }

    classify() {
      ip="$1"
      deleting="$2"
      if [ -n "$deleting" ] || [ -z "$ip" ]; then
        echo inactive
        return
      fi
      info=$(curl -fsS --max-time 2 "http://${ip}:${port}/system/gwinfo" 2>/dev/null || true)
      if [ -z "$info" ]; then
        echo unknown
        return
      fi
      case "$info" in
        *"ContextStatus=RUNNING;"*) ;;
        *)
          echo inactive
          return
          ;;
      esac
      case "$info" in
        *"RedundantNodeActiveStatus=Active;"*) ;;
        *"RedundantNodeActiveStatus="*)
          echo inactive
          return
          ;;
      esac
      case "$info" in
        *"RedundancyStatus=Master;"*) echo active-master ;;
        *) echo active ;;
      esac
    }

    log "started: namespace=${namespace} selector=${selector} label=${label} interval=${interval}s"
    streak=0
    loops=0
    while :; do
      loops=$((loops + 1))
      pods=$(kubectl get pods -n "$namespace" -l "$selector" \
        -o jsonpath="{range .items[*]}{.metadata.name}|{.status.podIP}|{.metadata.deletionTimestamp}|{.metadata.labels.${label}}{\"\n\"}{end}" 2>/dev/null)
      if [ -z "$pods" ]; then
        log "WARN: no gateway pods listed"
      else
        want=""
        other=""
        current=""
        current_state=""
        states=""
        while IFS='|' read -r name ip deleting has; do
          [ -n "$name" ] || continue
          state=$(classify "$ip" "$deleting")
          states="${states} ${name}=${state}"
          [ "$has" = "true" ] && current="$name" && current_state="$state"
          case "$state" in
            active-master) [ -n "$want" ] || want="$name" ;;
            active) [ -n "$other" ] || other="$name" ;;
          esac
        done <<EOF
    $pods
    EOF
        [ -n "$want" ] || want="$other"

        if [ -z "$want" ] && [ -n "$current" ] && [ "$current_state" = "unknown" ]; then
          streak=$((streak + 1))
          if [ "$streak" -lt "$unknown_hold" ]; then
            log "holding ${current}: no gwinfo answer (${streak}/${unknown_hold})"
            want="$current"
          fi
        else
          streak=0
        fi

        printf '%s\n' "$pods" | while IFS='|' read -r name ip deleting has; do
          [ -n "$name" ] || continue
          if [ "$name" = "$want" ] && [ "$has" != "true" ]; then
            kubectl label pod "$name" -n "$namespace" "${label}=true" --overwrite >/dev/null &&
              log "routing to ${name} (states:${states})"
          elif [ "$name" != "$want" ] && [ "$has" = "true" ]; then
            kubectl label pod "$name" -n "$namespace" "${label}-" >/dev/null &&
              log "no longer routing to ${name} (states:${states})"
          fi
        done
        [ -n "$want" ] || [ -z "$current" ] || log "WARN: no active gateway (states:${states})"
      fi
      [ "$max_loops" -gt 0 ] && [ "$loops" -ge "$max_loops" ] && exit 0
      sleep "$interval"
    done
  certify.sh: |-
    #!/bin/sh
    # Restarts gateways after their certificates are renewed. The preconfigure
    # init container copies the GAN and web certificates into the gateway on
    # every start, so a rolling restart is all a renewal needs.
    #
    # TARGETS is a space-separated list of "<statefulset>=<secret>,<secret>".
    # For each, the secrets' data is hashed and compared with the StatefulSet's
    # certify-hash annotation:
    #   - no annotation yet: record the hash (first run, no restart)
    #   - same hash: nothing to do
    #   - different: kubectl rollout restart, then record the new hash. The
    #     StatefulSet restarts the highest ordinal (the Backup) first and waits
    #     for it to be Ready before the Master.
    # A StatefulSet that is still rolling out is left for the next run.
    set -u

    namespace="${NAMESPACE}"
    status=0

    log() {
      printf '[certify] %s\n' "$*"
    }

    for target in ${TARGETS}; do
      sts="${target%%=*}"
      secrets=$(printf '%s' "${target#*=}" | tr ',' ' ')

      data=""
      missing=""
      for secret in $secrets; do
        if d=$(kubectl get secret "$secret" -n "$namespace" -o jsonpath='{.data}' 2>/dev/null) && [ -n "$d" ]; then
          data="${data}${secret}=${d};"
        else
          missing="${missing} ${secret}"
        fi
      done
      if [ -n "$missing" ]; then
        log "WARN: ${sts}: secrets not found:${missing}; skipping"
        status=1
        continue
      fi
      hash=$(printf '%s' "$data" | sha256sum | cut -c1-16)

      if ! current=$(kubectl get statefulset "$sts" -n "$namespace" -o jsonpath='{.metadata.annotations.certify-hash}' 2>/dev/null); then
        log "WARN: ${sts}: StatefulSet not found; skipping"
        status=1
        continue
      fi

      if [ -z "$current" ]; then
        kubectl annotate statefulset "$sts" -n "$namespace" "certify-hash=${hash}" --overwrite >/dev/null &&
          log "${sts}: recorded certificate hash ${hash}"
        continue
      fi
      if [ "$current" = "$hash" ]; then
        log "${sts}: certificates unchanged"
        continue
      fi

      settled=$(kubectl get statefulset "$sts" -n "$namespace" \
        -o jsonpath='{.status.replicas}/{.status.readyReplicas}/{.status.updatedReplicas}/{.status.currentRevision}/{.status.updateRevision}')
      replicas=$(printf '%s' "$settled" | cut -d/ -f1)
      ready=$(printf '%s' "$settled" | cut -d/ -f2)
      updated=$(printf '%s' "$settled" | cut -d/ -f3)
      current_rev=$(printf '%s' "$settled" | cut -d/ -f4)
      update_rev=$(printf '%s' "$settled" | cut -d/ -f5)
      if [ "$ready" != "$replicas" ] || [ "$updated" != "$replicas" ] || [ "$current_rev" != "$update_rev" ]; then
        log "${sts}: certificates renewed but a rollout is in progress (${ready}/${replicas} ready); will retry"
        continue
      fi

      if kubectl rollout restart statefulset "$sts" -n "$namespace" >/dev/null &&
        kubectl annotate statefulset "$sts" -n "$namespace" "certify-hash=${hash}" --overwrite >/dev/null; then
        log "${sts}: certificates renewed; rolling restart started (hash ${current} -> ${hash})"
      else
        log "ERROR: ${sts}: rolling restart failed"
        status=1
      fi
    done
    exit "$status"
  health-check.sh: |-
    #!/usr/bin/env bash
    # Health check for the Ignition Gateway: passes only when /StatusPing reports
    # the expected state (RUNNING by default). /StatusPing answers with
    # {"state":"..."} on both Ignition 8.1 and 8.3; /main/system/StatusPing does
    # not exist on either (8.1 redirects to a 404, 8.3 returns 404).
    #
    # -r (readiness) also fails while the gateway is still commissioning:
    # /StatusPing reports {"state":"RUNNING","details":"COMMISSIONING"} then.
    # Liveness leaves -r off so a gateway stuck commissioning is not restarted
    # in a loop (a restart does not finish commissioning).
    # With IGNITION_READY_REQUIRES_BACKUP_SYNC=true (set by activeRouting), -r
    # also fails on a Backup whose RedundantState is not Good, so a rolling
    # update only restarts the Master once the Backup has caught up.
    #
    # Usage: health-check.sh [-t <timeout seconds>] [-s <expected state>] [-r]

    HTTP_PORT=${IGNITION_HTTP_PORT:-8088}
    TIMEOUT=5
    EXPECTED_STATE=RUNNING
    READINESS=false

    while getopts ":t:s:r" opt; do
      case "${opt}" in
        t) TIMEOUT="${OPTARG}" ;;
        s) EXPECTED_STATE="${OPTARG}" ;;
        r) READINESS=true ;;
        *) echo "Usage: $0 [-t timeout] [-s state] [-r]" >&2; exit 2 ;;
      esac
    done

    if ! body=$(curl -s -f --max-time "${TIMEOUT}" "http://localhost:${HTTP_PORT}/StatusPing"); then
      echo "Gateway not responding on /StatusPing"
      exit 1
    fi

    case "${body}" in
      *"\"state\":\"${EXPECTED_STATE}\""*) ;;
      *) echo "Gateway state is not ${EXPECTED_STATE}: ${body}"; exit 1 ;;
    esac

    if [ "${READINESS}" = true ]; then
      case "${body}" in
        *"\"details\":\"COMMISSIONING\""*) echo "Gateway is still commissioning: ${body}"; exit 1 ;;
      esac
      if [ "${IGNITION_READY_REQUIRES_BACKUP_SYNC:-false}" = true ]; then
        if ! info=$(curl -s -f --max-time "${TIMEOUT}" "http://localhost:${HTTP_PORT}/system/gwinfo"); then
          echo "Gateway not responding on /system/gwinfo"
          exit 1
        fi
        case "${info}" in
          *"RedundancyStatus=Backup;"*)
            case "${info}" in
              *"RedundantState=Good;"*) ;;
              *) echo "Backup is not in sync with the Master: ${info}"; exit 1 ;;
            esac
            ;;
        esac
      fi
    fi
    exit 0
{{- end -}}
