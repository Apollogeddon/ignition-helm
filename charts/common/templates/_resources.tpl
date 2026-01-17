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

{{/*
GAN CA and Issuer
Params:
  context: The global context (Dot)
*/}}
{{- define "ignition-common.ganCA" -}}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ include "ignition.name" .context }}-gan-ca
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
spec:
  isCA: true
  commonName: {{ include "ignition.name" .context }}-gan-ca
  secretName: {{ include "ignition.name" .context }}-gan-ca
  privateKey:
    algorithm: ECDSA
    size: 256
  duration: 17520h0m0s  # 2 years
  issuerRef:
    name: {{ .context.Values.certManager.issuer.name }}
    kind: {{ .context.Values.certManager.issuer.kind }}
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: {{ include "ignition.name" .context }}-gan-issuer
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
spec:
  ca:
    secretName: {{ include "ignition.name" .context }}-gan-ca
{{- end }}

{{/*
GAN Metro Keystore Secret
Params:
  secrets: The component-specific secrets map
  context: The global context (Dot)
*/}}
{{- define "ignition-common.ganMetroKeystore" -}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "ignition.name" .context }}-gan-metro-keystore
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
type: Opaque
data:
  metro.keystore.password: {{ index .secrets "IGNITION_GAN_KEYSTORE_PASSWORD" | b64enc }}
{{- end }}

{{/*
GAN Certificate
Params:
  name: The component name suffix (e.g. "frontend" or "")
  commonName: The common name for the certificate
  dnsNames: List of DNS names
  context: The global context (Dot)
*/}}
{{- define "ignition-common.ganCertificate" -}}
{{- $fullname := include "ignition.name" .context }}
{{- if .name }}
{{- $fullname = printf "%s-%s-gan" $fullname .name }}
{{- else }}
{{- $fullname = printf "%s-gan" $fullname }}
{{- end }}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
spec:
  secretName: {{ $fullname }}-tls
  issuerRef:
    name: {{ include "ignition.name" .context }}-gan-issuer
    kind: Issuer
  commonName: {{ .commonName | quote }}
  dnsNames:
  {{- range .dnsNames }}
  - {{ . | quote }}
  {{- end }}
  duration: 8760h0m0s  # 1 year
  keystores:
    pkcs12:
      create: true
      passwordSecretRef:
        name: {{ include "ignition.name" .context }}-gan-metro-keystore
        key: metro.keystore.password
{{- end }}