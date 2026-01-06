{{/*
Expand the name of the chart.
*/}}
{{- define "ignition-common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ignition-common.fullname" -}}
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
{{- define "ignition-common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ignition-common.labels" -}}
helm.sh/chart: {{ include "ignition-common.chart" . }}
{{ include "ignition-common.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ignition-common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ignition-common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Logback XML Configuration
Params:
  level: The logging level (INFO, DEBUG, WARN, ERROR)
*/}}
{{- define "ignition-common.logback" -}}
<?xml version="1.0" encoding="UTF-8"?>
<!-- For assistance related to logback-translator or configuration  -->
<!-- files in general, please contact the logback user mailing list -->
<!-- at http://www.qos.ch/mailman/listinfo/logback-user             -->
<!--                                                                -->
<!-- For professional support please see                            -->
<!--    http://www.qos.ch/shop/products/professionalSupport         -->
<!--                                                                -->
<configuration debug="false">
  <appender name="SysoutAppender" class="ch.qos.logback.core.ConsoleAppender">
    <encoder>
      <pattern>%.-1p [%-30c{1}] [%d{HH:mm:ss.SSS}]: %m %X%n</pattern>
    </encoder>
  </appender>
  <appender name="DB" class="com.inductiveautomation.logging.SQLiteAppender">
    <dir>logs</dir>
    <!--
      Maintenance Settings
      entryLimit: The maximum number of entries in the database. However, at any given time, there may be more than this number, due to how cleanup works.
      maxEventsPerMaintenance: The number of event that can happen before a maintenance cycle occurs.
      minTimeBetweenMaintenance: The minimum time (max frequency) between maintenance events. Takes precedent over max events.
      vacuumFrequency: The number of maintenance cycles before a "vacuum" is performed, to recover disk space.
      diskspaceCleanupEventCount: The number of oldest events that will be removed when max database size is exceeded.
      maxDatabaseSize: Database size in bytes, above which will trigger a maintenance cycle to remove diskspaceCleanupEventCount of oldest events.

      On disk, most log events are between 600-800 bytes.
    <entryLimit>50000</entryLimit>
    <maxEventsPerMaintenance>5000</maxEventsPerMaintenance>
    <minTimeBetweenMaintenance>60000</minTimeBetweenMaintenance>
    <vacuumFrequency>3</vacuumFrequency>
    <diskspaceCleanupEventCount>500</diskspaceCleanupEventCount>
    <maxDatabaseSize>104857600</maxDatabaseSize>
    -->
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