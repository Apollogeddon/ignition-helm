{{/*
Standard Service Account
Params:
  values: The component-specific values object (containing serviceAccount key)
  context: The global context (Dot)
*/}}
{{- define "ignition-common.serviceAccount" -}}
{{- if .values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "ignition.serviceAccountName" .context }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
  {{- with .values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Standard ConfigMap
Params:
  name: The component name suffix (e.g. "frontend" or "")
  config: The config dictionary
  context: The global context (Dot)
*/}}
{{- define "ignition-common.configMap" -}}
{{- if .config }}
apiVersion: v1
kind: ConfigMap
metadata:
  {{- $fullname := include "ignition.name" .context }}
  {{- if .name }}
  {{- $fullname = printf "%s-%s-config" $fullname .name }}
  {{- else }}
  {{- $fullname = printf "%s-config" $fullname }}
  {{- end }}
  name: {{ $fullname }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
data: {{ .config | toYaml | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Standard Secret (supports SealedSecrets)
Params:
  name: The component name suffix (e.g. "frontend" or "")
  secrets: The secrets dictionary
  sealedSecrets: Boolean, whether to use SealedSecrets
  context: The global context (Dot)
*/}}
{{- define "ignition-common.secret" -}}
{{- if .secrets }}
{{- $fullname := include "ignition.name" .context }}
{{- if .name }}
{{- $fullname = printf "%s-%s-secrets" $fullname .name }}
{{- else }}
{{- $fullname = printf "%s-secrets" $fullname }}
{{- end }}
{{- if .sealedSecrets }}
# SealedSecrets
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
  annotations:
    sealedsecrets.bitnami.com/namespace-wide: "true"
spec:
  encryptedData:
    {{- range $key, $val := .secrets }}
    {{ $key }}: {{ $val | quote }}
    {{- end }}
{{- else }}
# Plain Kubernetes Secret
apiVersion: v1
kind: Secret
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
type: Opaque
data:
  {{- range $key, $value := .secrets }}
  {{ $key }}: {{ $value | b64enc | quote }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
