{{- define "opti-inference.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "opti-inference.labels" -}}
app.kubernetes.io/name: {{ include "opti-inference.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "opti-inference.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opti-inference.fullname" . }}
{{- end }}
