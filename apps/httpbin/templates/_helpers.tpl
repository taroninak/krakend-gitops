{{- define "httpbin.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "httpbin.labels" -}}
app.kubernetes.io/name: {{ include "httpbin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: krakend-poc
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "httpbin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "httpbin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
