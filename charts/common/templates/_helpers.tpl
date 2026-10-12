{{/*
Expand the name of the chart.
*/}}
{{- define "ignition.name" -}}
{{- default .Chart.Name .Values.applicationName | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ignition.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ignition.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ignition.labels" -}}
helm.sh/chart: {{ include "ignition.chart" . }}
{{ include "ignition.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ignition.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ignition.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ignition.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ignition.name" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
The gateway pods' service account and whether its API token is mounted
*/}}
{{- define "ignition-common.podServiceAccount" -}}
serviceAccountName: {{ include "ignition.serviceAccountName" . }}
automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken | default false }}
{{- end }}

{{/*
Create a default fully qualified app name for common resources.
*/}}
{{- define "ignition-common.fullname" -}}
{{- printf "%s-common" (include "ignition.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the name for the common scripts ConfigMap.
*/}}
{{- define "ignition-common.scriptsName" -}}
{{- include "ignition-common.fullname" . }}-scripts
{{- end -}}

{{/*
Common labels for common resources.
*/}}
{{- define "ignition-common.labels" -}}
helm.sh/chart: {{ include "ignition.chart" . }}
app.kubernetes.io/name: {{ include "ignition-common.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Standard Ingress
Params:
  name: The component name suffix (e.g. "frontend" or "")
  values: The component-specific values object
*/}}
{{- define "ignition-common.ingress" -}}
{{- if .values.ingress.enabled -}}
{{- $fullname := include "ignition.name" . }}
{{- if .name }}
{{- $fullname = printf "%s-%s" $fullname .name }}
{{- end }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "ignition.labels" . | nindent 4 }}
  {{- if .values.ingress.annotations }}
  annotations:
    {{- toYaml .values.ingress.annotations | nindent 4 }}
  {{- end }}
spec:
  {{- with .values.ingress.className }}
  ingressClassName: {{ . }}
  {{- end }}
  {{- if .values.ingress.tls }}
  tls:
    {{- range .values.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
  rules:
    {{- range .values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ $fullname }}{{ if include "ignition-common.activeRoutingEnabled" (dict "values" $.values) }}-active{{ end }}
                port:
                  number: {{ $.values.service.ports.http }}
          {{- end }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Standard Service
Params:
  name: The component name suffix (e.g. "frontend" or "")
  values: The component-specific values object
*/}}
{{- define "ignition-common.service" -}}
{{- $fullname := include "ignition.name" . }}
{{- if .name }}
{{- $fullname = printf "%s-%s" $fullname .name }}
{{- end }}
{{- $type := .values.service.type }}
{{- if include "ignition-common.activeRoutingEnabled" (dict "values" .values) }}
{{- /* the <name>-active Service takes the configured type, nodePorts and annotations */}}
{{- $type = "ClusterIP" }}
{{- end }}
apiVersion: v1
kind: Service
metadata:
  name: {{ $fullname }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ignition.labels" . | nindent 4 }}
    {{- with .name }}
    app.kubernetes.io/component: {{ . }}
    {{- end }}
  {{- if .values.service.annotations }}
  annotations:
    {{- toYaml .values.service.annotations | nindent 4 }}
  {{- end }}
spec:
  type: {{ $type }}
  {{- if .values.service.sessionAffinity }}
  sessionAffinity: {{ .values.service.sessionAffinity }}
  {{- end }}
  ports:
    - port: {{ .values.service.ports.http }}
      targetPort: http
      protocol: TCP
      name: http
      {{- if and (or (eq $type "NodePort") (eq $type "LoadBalancer")) .values.service.nodePorts }}
      {{- if .values.service.nodePorts.http }}
      nodePort: {{ .values.service.nodePorts.http }}
      {{- end }}
      {{- end }}
    - port: {{ .values.service.ports.https }}
      targetPort: https
      protocol: TCP
      name: https
      {{- if and (or (eq $type "NodePort") (eq $type "LoadBalancer")) .values.service.nodePorts }}
      {{- if .values.service.nodePorts.https }}
      nodePort: {{ .values.service.nodePorts.https }}
      {{- end }}
      {{- end }}
    - port: {{ .values.service.ports.gan }}
      targetPort: gan
      protocol: TCP
      name: gan
      {{- if and (or (eq $type "NodePort") (eq $type "LoadBalancer")) .values.service.nodePorts }}
      {{- if .values.service.nodePorts.gan }}
      nodePort: {{ .values.service.nodePorts.gan }}
      {{- end }}
      {{- end }}
  selector:
    {{- include "ignition.selectorLabels" . | nindent 4 }}
    {{- with .name }}
    app.kubernetes.io/component: {{ . }}
    {{- end }}
{{- end }}

{{/*
Standard Headless Service for StatefulSet identity
Params:
  name: The component name suffix (e.g. "frontend" or "")
  values: The component-specific values object
*/}}
{{- define "ignition-common.headlessService" -}}
{{- $fullname := include "ignition.name" . }}
{{- if .name }}
{{- $fullname = printf "%s-%s" $fullname .name }}
{{- end }}
apiVersion: v1
kind: Service
metadata:
  name: {{ $fullname }}-headless
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ignition.labels" . | nindent 4 }}
spec:
  clusterIP: None
  ports:
    - port: {{ .values.service.ports.http }}
      targetPort: http
      protocol: TCP
      name: http
    - port: {{ .values.service.ports.https }}
      targetPort: https
      protocol: TCP
      name: https
    - port: {{ .values.service.ports.gan }}
      targetPort: gan
      protocol: TCP
      name: gan
  selector:
    {{- include "ignition.selectorLabels" . | nindent 4 }}
    {{- with .name }}
    app.kubernetes.io/component: {{ . }}
    {{- end }}
{{- end }}

{{/*
Logback XML Configuration
Params:
  level: The logging level (INFO, DEBUG, WARN, ERROR)
  loggers: (Optional) Map of logger name -> level, e.g. {"gateway.SslManager": "DEBUG"}
  sqlite: (Optional) SQLiteAppender maintenance settings (entryLimit,
          maxEventsPerMaintenance, minTimeBetweenMaintenance, vacuumFrequency);
          unset keys keep Ignition's defaults
*/}}
{{- define "ignition-common.logback" -}}
<?xml version="1.0" encoding="UTF-8"?>
<configuration debug="false">
  <appender name="SysoutAppender" class="ch.qos.logback.core.ConsoleAppender">
    <encoder>
      <pattern>%.-1p [%-30c{1}] [%d{HH:mm:ss.SSS}]: %m %X%n</pattern>
    </encoder>
  </appender>
  <appender name="DB" class="com.inductiveautomation.logging.SQLiteAppender">
    <dir>logs</dir>
    {{- range $key := list "entryLimit" "maxEventsPerMaintenance" "minTimeBetweenMaintenance" "vacuumFrequency" }}
    {{- with (get ($.sqlite | default dict) $key) }}
    <{{ $key }}>{{ . }}</{{ $key }}>
    {{- end }}
    {{- end }}
  </appender>
  <appender name="SysoutAsync" class="ch.qos.logback.classic.AsyncAppender" queueSize="1000" discardingThreshold="0">
    <appender-ref ref="SysoutAppender" />
  </appender>
  <appender name="DBAsync" class="ch.qos.logback.classic.AsyncAppender" queueSize="100000" discardingThreshold="0">
    <appender-ref ref="DB" />
  </appender>
  <root level="{{ .level | default "INFO" }}">
    <appender-ref ref="SysoutAsync"/>
    <appender-ref ref="DBAsync"/>
  </root>
  {{- range $name, $level := (.loggers | default dict) }}
  <logger name="{{ $name }}" level="{{ $level }}" />
  {{- end }}
</configuration>
{{- end }}

{{/*
A whole number above 0, or the render fails naming the value; floats print
as whole numbers (1000000, not 1e+06)
Params:
  name: The value's path, for the error
  value: The value
*/}}
{{- define "ignition-common.positiveInt" -}}
{{- $v := .value }}
{{- if not (and (regexMatch "^[1-9][0-9]*$" (toString (int64 $v))) (eq (float64 (int64 $v)) (float64 $v))) }}
{{- fail (printf "%s must be a whole number above 0, not %v" .name $v) }}
{{- end }}
{{- int64 $v }}
{{- end }}

{{/*
Redundancy XML Properties
Params:
  role: Master or Backup
  host: The GAN host address
  port: The GAN port
  redundancy: The redundancy values object
*/}}
{{- define "ignition-common.redundancyXml" -}}
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">
<properties>
<comment>Redundancy Settings</comment>
<entry key="redundancy.noderole">{{ .role }}</entry>
<entry key="redundancy.gan.pingTimeout">{{ include "ignition-common.positiveInt" (dict "name" "redundancy.pingTimeout" "value" .redundancy.pingTimeout) }}</entry>
<entry key="redundancy.gan.pingMaxMissed">{{ include "ignition-common.positiveInt" (dict "name" "redundancy.pingMaxMissed" "value" .redundancy.pingMaxMissed) }}</entry>
<entry key="redundancy.activehistorylevel">Full</entry>
<entry key="redundancy.standbyactivitylevel">Cold</entry>
<entry key="redundancy.gan.pingRate">{{ include "ignition-common.positiveInt" (dict "name" "redundancy.pingRate" "value" .redundancy.pingRate) }}</entry>
<entry key="redundancy.bindinterface"></entry>
<entry key="redundancy.gan.enableSsl">{{ .redundancy.enableSsl }}</entry>
<entry key="redundancy.backupreconnectperiod">10000</entry>
<entry key="redundancy.joinwaittime">{{ include "ignition-common.positiveInt" (dict "name" "redundancy.joinWaitTime" "value" .redundancy.joinWaitTime) }}</entry>
<entry key="redundancy.gan.websocketTimeout">{{ include "ignition-common.positiveInt" (dict "name" "redundancy.websocketTimeout" "value" .redundancy.websocketTimeout) }}</entry>
<entry key="redundancy.systemstaterevision">0</entry>
<entry key="redundancy.sync.timeoutSecs">{{ include "ignition-common.positiveInt" (dict "name" "redundancy.syncTimeoutSecs" "value" .redundancy.syncTimeoutSecs) }}</entry>
<entry key="redundancy.maxdisk_mb">{{ include "ignition-common.positiveInt" (dict "name" "redundancy.maxDiskMb" "value" .redundancy.maxDiskMb) }}</entry>
<entry key="redundancy.systemstateuid">00000000-0000-0000-0000-000000000000</entry>
{{- if not (has .redundancy.masterRecoveryMode (list "Automatic" "Manual")) }}
{{- fail (printf "redundancy.masterRecoveryMode must be Automatic or Manual, not %v" .redundancy.masterRecoveryMode) }}
{{- end }}
<entry key="redundancy.masterrecoverymode">{{ .redundancy.masterRecoveryMode }}</entry>
<entry key="redundancy.gan.httpConnectTimeout">{{ include "ignition-common.positiveInt" (dict "name" "redundancy.httpConnectTimeout" "value" .redundancy.httpConnectTimeout) }}</entry>
<entry key="redundancy.gan.httpReadTimeout">{{ include "ignition-common.positiveInt" (dict "name" "redundancy.httpReadTimeout" "value" .redundancy.httpReadTimeout) }}</entry>
<entry key="redundancy.gan.host">{{ .host }}</entry>
<entry key="redundancy.backupfailovertimeout">{{ include "ignition-common.positiveInt" (dict "name" "redundancy.backupFailoverTimeout" "value" .redundancy.backupFailoverTimeout) }}</entry>
<entry key="redundancy.gan.port">{{ .port }}</entry>
<entry key="redundancy.autodetectlocalinterface">true</entry>
</properties>
{{- end }}

{{/*
Standard Probes
Params:
  probe: The probe values object (livenessProbe or readinessProbe)
*/}}
{{- define "ignition-common.probes" -}}
exec:
  command: {{- toYaml .probe.command | nindent 4 }}
initialDelaySeconds: {{ .probe.initialDelaySeconds }}
periodSeconds: {{ .probe.periodSeconds }}
failureThreshold: {{ .probe.failureThreshold }}
timeoutSeconds: {{ .probe.timeoutSeconds }}
{{- end }}

{{/*
Probe with a default command
Values win over the default: the probe's own `command` is used when set, and
the chart's health-check script only when it is empty. (A plain `merge` gives
the first dict precedence, which silently replaced any configured command.)
Params:
  probe: The probe values object (readinessProbe, livenessProbe or startupProbe)
*/}}
{{- define "ignition-common.probeWithDefault" -}}
{{- $probe := mergeOverwrite (dict "command" (list "/config/scripts/health-check.sh")) (deepCopy .probe) -}}
{{- if not $probe.command }}
{{- $_ := set $probe "command" (list "/config/scripts/health-check.sh") }}
{{- end }}
{{- include "ignition-common.probes" (dict "probe" $probe) }}
{{- end }}

{{/*
Restore enabled: restore.enabled with a url or path to take the backup from.
Renders "true" or nothing.
Params:
  values: The component-specific values object
*/}}
{{- define "ignition-common.restoreEnabled" -}}
{{- $restore := .values.restore | default dict }}
{{- if and $restore.enabled (or $restore.url $restore.path) }}true{{ end }}
{{- end }}

{{/*
Gateway container args
Renders .values.args and, when logging.wrapperLogToStdout is set, appends the
wrapper property wrapper.logfile=/dev/stdout (after "--", added if missing) so
the gateway log goes to the container log instead of an unrotated
logs/wrapper.log on the logs emptyDir. Skipped when args already set
wrapper.logfile. With restore enabled and a url or path set, it prepends
-r with the backup configure-ignition.sh stages on the data volume: the
Ignition image restores it on the gateway's first start only.
Params:
  values: The component-specific values object
*/}}
{{- define "ignition-common.args" -}}
{{- $args := .values.args | default list }}
{{- if include "ignition-common.restoreEnabled" . }}
{{- $args = concat (list "-r" "/usr/local/bin/ignition/data/restore.gwbk") $args }}
{{- end }}
{{- $logging := .values.logging | default dict }}
{{- if and $logging.wrapperLogToStdout (not (regexMatch "(^| )wrapper\\.logfile=" (join " " $args))) }}
{{- if not (has "--" $args) }}
{{- $args = append $args "--" }}
{{- end }}
{{- $args = append $args "wrapper.logfile=/dev/stdout" }}
{{- end }}
{{- with $args }}
args:
{{- toStrings . | toYaml | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Gateway container probes and lifecycle
Renders readinessProbe/livenessProbe/startupProbe (each when enabled) and the
lifecycle block (only when set - there is no default preStop: on SIGTERM the
gateway already shuts down gracefully, and `gwcmd.sh -p` resets the gateway
login password on Ignition 8.1 and 8.3).
Params:
  values: The component-specific values object
*/}}
{{- define "ignition-common.containerProbes" -}}
{{- with .values.lifecycle }}
lifecycle:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if .values.readinessProbe.enabled }}
readinessProbe:
  {{- include "ignition-common.probeWithDefault" (dict "probe" .values.readinessProbe) | nindent 2 }}
{{- end }}
{{- if .values.livenessProbe.enabled }}
livenessProbe:
  {{- include "ignition-common.probeWithDefault" (dict "probe" .values.livenessProbe) | nindent 2 }}
{{- end }}
{{- if and .values.startupProbe .values.startupProbe.enabled }}
startupProbe:
  {{- include "ignition-common.probeWithDefault" (dict "probe" .values.startupProbe) | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Standard Volume Mounts
Params:
  name: The base name of the application/component
  values: The component-specific values object
*/}}
{{- define "ignition-common.volumeMounts" -}}
- mountPath: /usr/local/bin/ignition/data
  name: data
- mountPath: /usr/local/bin/ignition/logs
  name: {{ .name }}-logs
- mountPath: /usr/local/bin/ignition/temp
  name: {{ .name }}-temp
- mountPath: /usr/local/bin/ignition/.ignition
  name: {{ .name }}-dot-ignition
- mountPath: {{ include "ignition-common.scriptMountPath" . }}
  name: {{ .name }}-config-scripts
  readOnly: true
- mountPath: /run/secrets/gan-tls
  name: {{ .name }}-gan-tls
  readOnly: true
{{- if and .values.ssl .values.ssl.enabled }}
- mountPath: /run/secrets/web-tls
  name: {{ .name }}-web-tls
  readOnly: true
{{- end }}
{{- if .values.localMounts }}
{{- range $index, $localMounts := .values.localMounts }}
- mountPath: /usr/local/bin/ignition/{{ $localMounts.mountPath }}
  name: local-mount-{{ $index }}
{{- end }}
{{- end }}
{{- if .values.extraVolumeMounts }}
{{- toYaml .values.extraVolumeMounts | nindent 0 }}
{{- end }}
{{- if and .values.externalModules .values.externalModules.enabled }}
- mountPath: /usr/local/bin/ignition/user-lib/modules
  name: external-modules
{{- end }}
{{- end }}

{{/*
Standard Volumes
Params:
  name: The base name of the application/component
  values: The component-specific values object
  ganTlsSecretName: The secret name for GAN TLS
  commonScriptsConfigMapName: The name of the common scripts configmap
*/}}
{{- define "ignition-common.volumes" -}}
- name: {{ .name }}-config-scripts
  secret:
    secretName: {{ .commonScriptsConfigMapName }}
    defaultMode: 0755
{{- $limits := .values.emptyDirSizeLimit | default dict }}
- name: {{ .name }}-logs
  emptyDir: {{ if $limits.logs }}{ sizeLimit: {{ $limits.logs }} }{{ else }}{}{{ end }}
- name: {{ .name }}-temp
  emptyDir: {{ if $limits.temp }}{ sizeLimit: {{ $limits.temp }} }{{ else }}{}{{ end }}
- name: {{ .name }}-dot-ignition
  emptyDir: {{ if $limits.dotIgnition }}{ sizeLimit: {{ $limits.dotIgnition }} }{{ else }}{}{{ end }}
- name: {{ .name }}-config-files
  secret:
    secretName: {{ .name }}-config-files
    defaultMode: 0644
- name: {{ .name }}-gan-ca
  secret:
    secretName: {{ .name }}-gan-ca
- name: {{ .name }}-gan-tls
  secret:
    secretName: {{ .ganTlsSecretName }}
{{- if and .values.ssl .values.ssl.enabled }}
- name: {{ .name }}-web-tls
  secret:
    secretName: {{ .values.ssl.secretName | default (printf "%s-web-tls" .name) }}
{{- end }}
{{- if .values.localMounts }}
{{- range $index, $localMounts := .values.localMounts }}
- name: local-mount-{{ $index }}
  hostPath:
    path: {{ $localMounts.hostPath }}
    type: Directory
{{- end }}
{{- end }}
{{- if .values.extraVolumes }}
{{- toYaml .values.extraVolumes | nindent 0 }}
{{- end }}
{{- if and .values.externalModules .values.externalModules.enabled }}
- name: external-modules
  persistentVolumeClaim:
    claimName: {{ .values.externalModules.pvcName }}
{{- end }}
{{- end }}

{{/*
Preconfigure Init Container
Params:
  name: The base name of the application/component
  image: The image definition (repository and tag)
  values: The component-specific values object
  replicas: Number of replicas (for redundancy initialization)
*/}}
{{/*
Init container that gives the data volume to the gateway user
(<values>.fixDataOwnership). Charts up to 3.1.0 ran the gateway as root by
default, so their data volumes are owned by root and the non-root gateway
cannot update them after an upgrade. Storage that does not apply fsGroup
(e.g. local-path) keeps that ownership. Runs as root with only the CHOWN,
DAC_OVERRIDE and FOWNER capabilities, so the namespace must allow the
baseline Pod Security level; turn it off again once the volumes are fixed.
Params:
  image: The image repo/tag reference
  values: The component-specific values object
  context: The global context (Dot)
*/}}
{{- define "ignition-common.initContainer.fixDataOwnership" -}}
{{- if .values.fixDataOwnership }}
{{- $owner := printf "%v:%v" .values.securityContext.runAsUser .values.securityContext.runAsGroup }}
- name: fix-data-ownership
  image: {{ .image.repository }}:{{ .image.tag | default .context.Chart.AppVersion }}
  imagePullPolicy: {{ .image.pullPolicy }}
  command: ["sh", "-c", "chown -R {{ $owner }} /data && echo 'data volume owned by {{ $owner }}'"]
  securityContext:
    runAsUser: 0
    runAsNonRoot: false
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
      add: ["CHOWN", "DAC_OVERRIDE", "FOWNER"]
  volumeMounts:
  - mountPath: /data
    name: data
{{- end }}
{{- end }}

{{- define "ignition-common.initContainer.preconfigure" -}}
{{- $secretName := .secretName | default (printf "%s-secrets" .name) -}}
- name: preconfigure
  image: {{ .image.repository }}:{{ .image.tag | default .context.Chart.AppVersion }}
  imagePullPolicy: {{ .image.pullPolicy }}
  {{- if .values.initResources }}
  resources:
    {{- toYaml .values.initResources | nindent 4 }}
  {{- end }}
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
    readOnlyRootFilesystem: true
    runAsGroup: {{ .values.securityContext.runAsGroup }}
    runAsNonRoot: {{ .values.securityContext.runAsNonRoot }}
    runAsUser: {{ .values.securityContext.runAsUser }}
  env:
  - name: TLS_KEYSTORE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ $secretName }}
        key: IGNITION_WEB_KEYSTORE_PASSWORD
  - name: METRO_KEYSTORE_PASSPHRASE
    valueFrom:
      secretKeyRef:
        name: {{ $secretName }}
        key: IGNITION_GAN_KEYSTORE_PASSWORD
  - name: IGNITION_REPLICAS
    value: {{ .replicas | quote }}
  {{- if .values.restore }}
  {{- if .values.restore.enabled }}
  {{- if .values.restore.url }}
  - name: IGNITION_RESTORE_URL
    value: {{ .values.restore.url | quote }}
  {{- end }}
  {{- if .values.restore.path }}
  - name: IGNITION_RESTORE_PATH
    value: {{ .values.restore.path | quote }}
  {{- end }}
  {{- end }}
  {{- end }}
  command:
  - {{ include "ignition-common.scriptMountPath" . }}/invoke-args.sh
  args:
  - {{ include "ignition-common.scriptMountPath" . }}/seed-data-volume.sh
  - {{ include "ignition-common.scriptMountPath" . }}/seed-redundancy.sh
  - {{ include "ignition-common.scriptMountPath" . }}/prepare-gan-certificates.sh
  {{- if and .values.ssl .values.ssl.enabled }}
  - {{ include "ignition-common.scriptMountPath" . }}/prepare-tls-certificates.sh
  {{- end }}
  - cp /config/files/logback.xml /data/logback.xml
  - {{ include "ignition-common.scriptMountPath" . }}/configure-ignition.sh
  volumeMounts:
  - mountPath: /data
    name: data
  - mountPath: /config/files
    name: {{ .name }}-config-files
  - mountPath: {{ include "ignition-common.scriptMountPath" . }}
    name: {{ .name }}-config-scripts
  - mountPath: /run/secrets/gan-tls
    name: {{ .name }}-gan-tls
  {{- if and .values.ssl .values.ssl.enabled }}
  - mountPath: /run/secrets/web-tls
    name: {{ .name }}-web-tls
    readOnly: true
  {{- end }}
  - mountPath: /run/secrets/ignition-gan-ca
    name: {{ .name }}-gan-ca
    readOnly: true
{{- end }}

{{/*
Script Mount Path
*/}}
{{- define "ignition-common.scriptMountPath" -}}
/config/scripts
{{- end }}

{{/*
Pod FQDN Helper
Params:
  name: The name of the StatefulSet/Service (e.g. "ignition-failover" or "ignition-scaleout-backend")
  ordinal: The pod ordinal index
*/}}
{{- define "ignition-common.podFQDN" -}}
{{- printf "%s-%d.%s-headless" .name (int .ordinal) .name -}}
{{- end }}

{{/*
Standard Affinity
Spreads the release's pods of one component (all its pods when no component
is given), so scaleout's frontends and backends don't repel each other.
Params:
  affinity: The affinity values object
  context: The global context (Dot)
  component: The pods' app.kubernetes.io/component label (optional)
*/}}
{{- define "ignition-common.affinity" -}}
{{- if .affinity.enabled }}
{{- $type := .affinity.type | default "soft" }}
{{- if not (has $type (list "soft" "hard")) }}
{{- fail (printf "affinity.type must be soft or hard, not %v" $type) }}
{{- end }}
{{- $selector := include "ignition.selectorLabels" .context | fromYaml }}
{{- if .component }}
{{- $_ := set $selector "app.kubernetes.io/component" .component }}
{{- end }}
{{- $term := dict "labelSelector" (dict "matchLabels" $selector) "topologyKey" .affinity.topologyKey }}
affinity:
  podAntiAffinity:
    {{- if eq $type "soft" }}
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        {{- toYaml $term | nindent 8 }}
    {{- else }}
    requiredDuringSchedulingIgnoredDuringExecution:
    - {{ toYaml $term | indent 6 | trim }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
StatefulSet update strategy
Renders the body of a StatefulSet's updateStrategy: the type and, for
RollingUpdate, a partition of 0 so every pod is updated.
Params:
  values: The component-specific values object
*/}}
{{- define "ignition-common.updateStrategy" -}}
type: {{ .values.updateStrategy.type }}
{{- if eq .values.updateStrategy.type "RollingUpdate" }}
rollingUpdate:
  partition: 0
{{- end }}
{{- end }}

{{/*
Gateway pod securityContext
The pod-level securityContext from .values.securityContext, with the
RuntimeDefault seccomp profile the restricted Pod Security level requires.
Params:
  values: The component-specific values object
*/}}
{{- define "ignition-common.podSecurityContext" -}}
securityContext:
  fsGroup: {{ .values.securityContext.fsGroup }}
  runAsGroup: {{ .values.securityContext.runAsGroup }}
  runAsNonRoot: {{ .values.securityContext.runAsNonRoot }}
  runAsUser: {{ .values.securityContext.runAsUser }}
  seccompProfile:
    type: RuntimeDefault
{{- end }}

{{/*
Gateway container
The start of the gateway container, as a list item: its name, securityContext,
image, resources, args and ports. The chart adds envFrom, env, volumeMounts and
probes after it, as those differ between components.
Params:
  image: The image values object
  values: The component-specific values object
  context: The global context (Dot)
*/}}
{{- define "ignition-common.gatewayContainer" -}}
- name: gateway
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
    readOnlyRootFilesystem: false
  image: {{ .image.repository }}:{{ .image.tag | default .context.Chart.AppVersion }}
  imagePullPolicy: {{ .image.pullPolicy }}
  resources: {{ .values.resources | toYaml | nindent 4 }}
  {{- include "ignition-common.args" (dict "values" .values) | nindent 2 }}
  ports:
  - name: http
    containerPort: {{ .values.service.ports.http }}
  - name: https
    containerPort: {{ .values.service.ports.https }}
  - name: gan
    containerPort: {{ .values.service.ports.gan }}
{{- end }}

{{/*
Gateway data volume claim
The StatefulSet's volumeClaimTemplates for the gateway's data volume. A
storageClassName of "-" sets an empty class, which disables dynamic
provisioning; an empty one leaves the cluster's default class.
Params:
  values: The component-specific values object
*/}}
{{- define "ignition-common.volumeClaimTemplates" -}}
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    accessModes: {{- toYaml .values.persistence.accessModes | nindent 6 }}
  {{- if .values.persistence.storageClassName }}
  {{- if (eq "-" .values.persistence.storageClassName) }}
    storageClassName: ""
  {{- else }}
    storageClassName: "{{ .values.persistence.storageClassName }}"
  {{- end }}
  {{- end }}
    resources:
      requests:
        storage: {{ .values.persistence.size }}
{{- end }}
