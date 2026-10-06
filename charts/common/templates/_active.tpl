{{/*
Active-node routing for a redundant pair (activeRouting.enabled with
redundancy.enabled).

Pod readiness decides two things: which pods a Service sends traffic to, and
whether a StatefulSet rolling update may continue. A redundant pair needs
these answered differently. Users must only reach the gateway that is Active,
but a cold Backup that is healthy and in sync must count as Ready, or the
OrderedReady rolling update stalls. So:

  - readiness means "running, commissioned and, for a Backup, in sync with the
    Master" (health-check.sh -r with IGNITION_READY_REQUIRES_BACKUP_SYNC);
  - a small labeller Deployment polls each gateway's /system/gwinfo and keeps
    the label redundancy-active=true on the Active gateway (preferring the
    Master during a failback overlap);
  - the <name>-active Service selects only the labelled pod and publishes it
    regardless of readiness. It takes the configured service type, nodePorts
    and annotations; the main Service becomes ClusterIP. The chart Ingress
    points at it.
*/}}

{{/*
"true" when active routing applies to this component
Params:
  values: The component-specific values object
*/}}
{{- define "ignition-common.activeRoutingEnabled" -}}
{{- if and .values.activeRouting .values.activeRouting.enabled .values.redundancy .values.redundancy.enabled -}}
true
{{- end -}}
{{- end }}

{{/*
Active routing resources: ServiceAccount, Role, RoleBinding, labeller
Deployment and the <name>-active Service
Params:
  name: The component name suffix (e.g. "backend" or "")
  values: The component-specific values object
  context: The global context (Dot)
*/}}
{{- define "ignition-common.activeRouting" -}}
{{- if include "ignition-common.activeRoutingEnabled" (dict "values" .values) }}
{{- $fullname := include "ignition.name" .context }}
{{- if .name }}
{{- $fullname = printf "%s-%s" $fullname .name }}
{{- end }}
{{- $ar := .values.activeRouting }}
{{- $selector := printf "app.kubernetes.io/name=%s,app.kubernetes.io/instance=%s" (include "ignition.name" .context) .context.Release.Name }}
{{- if .name }}
{{- $selector = printf "%s,app.kubernetes.io/component=%s" $selector .name }}
{{- end }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $fullname }}-active
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ $fullname }}-active
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
rules:
  # list can't be restricted by resourceNames
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods"]
    resourceNames: [{{ printf "%s-0" $fullname | quote }}, {{ printf "%s-1" $fullname | quote }}]
    verbs: ["patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ $fullname }}-active
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
subjects:
  - kind: ServiceAccount
    name: {{ $fullname }}-active
    namespace: {{ .context.Release.Namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ $fullname }}-active
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $fullname }}-active
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ $fullname }}-active
      app.kubernetes.io/instance: {{ .context.Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ $fullname }}-active
        app.kubernetes.io/instance: {{ .context.Release.Name }}
      annotations:
        checksum/scripts: {{ include "ignition-common.scripts" .context | sha256sum }}
    spec:
      serviceAccountName: {{ $fullname }}-active
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: active
          image: {{ $ar.image | default "alpine/kubectl:1.34.1" }}
          command: ["/bin/sh", "/config/scripts/active-routing.sh"]
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
            - name: POD_SELECTOR
              value: {{ $selector | quote }}
            - name: ACTIVE_LABEL
              value: redundancy-active
            - name: HTTP_PORT
              value: {{ .values.service.ports.http | quote }}
            - name: INTERVAL_SECONDS
              value: {{ $ar.intervalSeconds | default 2 | quote }}
            - name: UNKNOWN_HOLD
              value: {{ $ar.unknownHold | default 3 | quote }}
          resources:
            {{- toYaml ($ar.resources | default (dict "requests" (dict "cpu" "10m" "memory" "32Mi") "limits" (dict "cpu" "200m" "memory" "128Mi"))) | nindent 12 }}
          volumeMounts:
            - name: scripts
              mountPath: /config/scripts
              readOnly: true
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: scripts
          configMap:
            name: {{ include "ignition-common.scriptsName" .context }}
            defaultMode: 0755
        - name: tmp
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $fullname }}-active
  namespace: {{ .context.Release.Namespace }}
  labels:
    {{- include "ignition.labels" .context | nindent 4 }}
  {{- with .values.service.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ .values.service.type }}
  publishNotReadyAddresses: true
  {{- if .values.service.sessionAffinity }}
  sessionAffinity: {{ .values.service.sessionAffinity }}
  {{- end }}
  ports:
    {{- range $port := list "http" "https" }}
    - port: {{ get $.values.service.ports $port }}
      targetPort: {{ $port }}
      protocol: TCP
      name: {{ $port }}
      {{- if and (has $.values.service.type (list "NodePort" "LoadBalancer")) $.values.service.nodePorts }}
      {{- with get $.values.service.nodePorts $port }}
      nodePort: {{ . }}
      {{- end }}
      {{- end }}
    {{- end }}
  selector:
    {{- include "ignition.selectorLabels" .context | nindent 4 }}
    {{- with .name }}
    app.kubernetes.io/component: {{ . }}
    {{- end }}
    redundancy-active: "true"
{{- end }}
{{- end }}
