{{- define "ignition-common.scripts" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "ignition-common.fullname" . }}-scripts
  labels:
    {{- include "ignition-common.labels" . | nindent 4 }}
data:
  seed-data-volume.sh: |-
    {{- .Files.Get "scripts/seed-data-volume.sh" | nindent 4 }}
  seed-redundancy.sh: |-
    {{- .Files.Get "scripts/seed-redundancy.sh" | nindent 4 }}
  prepare-gan-certificates.sh: |-
    {{- .Files.Get "scripts/prepare-gan-certificates.sh" | nindent 4 }}
  prepare-tls-certificates.sh: |-
    {{- .Files.Get "scripts/prepare-tls-certificates.sh" | nindent 4 }}
  invoke-args.sh: |-
    {{- .Files.Get "scripts/invoke-args.sh" | nindent 4 }}
  configure-ignition.sh: |-
    {{- .Files.Get "scripts/configure-ignition.sh" | nindent 4 }}
{{- end -}}
