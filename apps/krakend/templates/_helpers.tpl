{{- define "krakend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "krakend.labels" -}}
app.kubernetes.io/name: {{ include "krakend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/part-of: krakend-poc
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "krakend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "krakend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "krakend.configFileName" -}}
{{- base .Values.config.file -}}
{{- end -}}
