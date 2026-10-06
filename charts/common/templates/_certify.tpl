{{/*
Restart on certificate renewal (certManager.restartOnRenewal.enabled)

The preconfigure init container copies the GAN CA, GAN certificate and web
certificate into the gateway on every start, but a running gateway does not
re-read them. This CronJob hashes the certificate secrets and starts a
rolling restart of a StatefulSet when its hash changes (certify.sh).

Params:
  targets: list of dicts (statefulset: name, secrets: list of secret names)
  context: The global context (Dot)
*/}}
{{- define "ignition-common.certify" -}}
{{- $r := .context.Values.certManager.restartOnRenewal | default dict }}
{{- if $r.enabled }}
{{- $name := printf "%s-certify" (include "ignition.name" .context) }}
{{- $stsNames := list }}
{{- $secretNames := list }}
{{- $targets := list }}
{{- range .targets }}
{{- $stsNames = append $stsNames .statefulset }}
{{- $secretNames = concat $secretNames .secrets }}
{{- $targets = append $targets (printf "%s=%s" .statefulset (join "," .secrets)) }}
{{- end }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $name }}
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ $name }}
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: {{ toJson (uniq $secretNames) }}
    verbs: ["get"]
  - apiGroups: ["apps"]
    resources: ["statefulsets"]
    resourceNames: {{ toJson $stsNames }}
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ $name }}
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
subjects:
  - kind: ServiceAccount
    name: {{ $name }}
    namespace: {{ .context.Release.Namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ $name }}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ $name }}
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
spec:
  schedule: {{ $r.schedule | default "*/15 * * * *" | quote }}
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 0
      template:
        metadata:
          labels:
            app.kubernetes.io/name: {{ $name }}
            app.kubernetes.io/instance: {{ .context.Release.Name }}
        spec:
          serviceAccountName: {{ $name }}
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: certify
              image: {{ $r.image | default "alpine/kubectl:1.34.1" }}
              command: ["/bin/sh", "/config/scripts/certify.sh"]
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop: ["ALL"]
              env:
                - name: HOME
                  value: /tmp
                - name: NAMESPACE
                  valueFrom:
                    fieldRef:
                      fieldPath: metadata.namespace
                - name: TARGETS
                  value: {{ join " " $targets | quote }}
              resources:
                requests: {cpu: 10m, memory: 32Mi}
                limits: {cpu: 200m, memory: 128Mi}
              volumeMounts:
                - name: scripts
                  mountPath: /config/scripts
                  readOnly: true
                - name: tmp
                  mountPath: /tmp
          volumes:
            - name: scripts
              secret:
                secretName: {{ include "ignition-common.scriptsName" .context }}
                defaultMode: 0755
            - name: tmp
              emptyDir: {}
{{- end }}
{{- end }}
