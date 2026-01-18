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
                name: {{ $fullname }}
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
apiVersion: v1
kind: Service
metadata:
  name: {{ $fullname }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ignition.labels" . | nindent 4 }}
  {{- if .values.service.annotations }}
  annotations:
    {{- toYaml .values.service.annotations | nindent 4 }}
  {{- end }}
spec:
  type: {{ .values.service.type }}
  {{- if .values.service.sessionAffinity }}
  sessionAffinity: {{ .values.service.sessionAffinity }}
  {{- end }}
  ports:
    - port: {{ .values.service.ports.http }}
      targetPort: http
      protocol: TCP
      name: http
      {{- if and (or (eq .values.service.type "NodePort") (eq .values.service.type "LoadBalancer")) .values.service.nodePorts }}
      {{- if .values.service.nodePorts.http }}
      nodePort: {{ .values.service.nodePorts.http }}
      {{- end }}
      {{- end }}
    - port: {{ .values.service.ports.https }}
      targetPort: https
      protocol: TCP
      name: https
      {{- if and (or (eq .values.service.type "NodePort") (eq .values.service.type "LoadBalancer")) .values.service.nodePorts }}
      {{- if .values.service.nodePorts.https }}
      nodePort: {{ .values.service.nodePorts.https }}
      {{- end }}
      {{- end }}
    - port: {{ .values.service.ports.gan }}
      targetPort: gan
      protocol: TCP
      name: gan
      {{- if and (or (eq .values.service.type "NodePort") (eq .values.service.type "LoadBalancer")) .values.service.nodePorts }}
      {{- if .values.service.nodePorts.gan }}
      nodePort: {{ .values.service.nodePorts.gan }}
      {{- end }}
      {{- end }}
  selector:
    {{- include "ignition.selectorLabels" . | nindent 4 }}
{{- end }}

{{/*
Logback XML Configuration
Params:
  level: The logging level (INFO, DEBUG, WARN, ERROR)
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
  <logger name="gateway.SslManager" level="DEBUG" />
</configuration>
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
<entry key="redundancy.gan.pingTimeout">{{ .redundancy.pingTimeout }}</entry>
<entry key="redundancy.gan.pingMaxMissed">{{ .redundancy.pingMaxMissed }}</entry>
<entry key="redundancy.activehistorylevel">Full</entry>
<entry key="redundancy.standbyactivitylevel">Cold</entry>
<entry key="redundancy.gan.pingRate">{{ .redundancy.pingRate }}</entry>
<entry key="redundancy.bindinterface"></entry>
<entry key="redundancy.gan.enableSsl">{{ .redundancy.enableSsl }}</entry>
<entry key="redundancy.backupreconnectperiod">10000</entry>
<entry key="redundancy.joinwaittime">{{ .redundancy.joinWaitTime }}</entry>
<entry key="redundancy.gan.websocketTimeout">{{ .redundancy.websocketTimeout }}</entry>
<entry key="redundancy.systemstaterevision">0</entry>
<entry key="redundancy.sync.timeoutSecs">{{ .redundancy.syncTimeoutSecs }}</entry>
<entry key="redundancy.maxdisk_mb">{{ .redundancy.maxDiskMb }}</entry>
<entry key="redundancy.systemstateuid">00000000-0000-0000-0000-000000000000</entry>
<entry key="redundancy.masterrecoverymode">{{ .redundancy.masterRecoveryMode }}</entry>
<entry key="redundancy.gan.httpConnectTimeout">{{ .redundancy.httpConnectTimeout }}</entry>
<entry key="redundancy.gan.httpReadTimeout">{{ .redundancy.httpReadTimeout }}</entry>
<entry key="redundancy.gan.host">{{ .host }}</entry>
<entry key="redundancy.backupfailovertimeout">{{ .redundancy.backupFailoverTimeout }}</entry>
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
Standard Volume Mounts
Params:
  name: The base name of the application/component
  values: The component-specific values object
  machineIdSubPath: (Optional) The subPath for machine-id
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
{{- if .values.spoofMachineId }}
- mountPath: /etc/machine-id
  name: {{ .name }}-config-files
  subPath: {{ .machineIdSubPath | default "machine-id" }}
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
- name: {{ .name }}-logs
  emptyDir: {}
- name: {{ .name }}-temp
  emptyDir: {}
- name: {{ .name }}-dot-ignition
  emptyDir: {}
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
{{- end }}

{{/*
Preconfigure Init Container
Params:
  name: The base name of the application/component
  image: The image definition (repository and tag)
  values: The component-specific values object
  replicas: Number of replicas (for redundancy initialization)
*/}}
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
  - name: SPOOF_MACHINE_ID
    value: {{ .values.spoofMachineId | default "" | quote }}
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
  {{- if gt (int .replicas) 1 }}
  - {{ include "ignition-common.scriptMountPath" . }}/seed-redundancy.sh
  {{- end }}
  - {{ include "ignition-common.scriptMountPath" . }}/prepare-gan-certificates.sh
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
{{- printf "%s-%d.%s" .name (int .ordinal) .name -}}
{{- end }}