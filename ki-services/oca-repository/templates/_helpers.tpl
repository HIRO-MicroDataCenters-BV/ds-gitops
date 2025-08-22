{{/*
App name
*/}}
{{- define "oca-repository.name" -}}
oca-repository
{{- end }}

{{/*
Fullname
*/}}
{{- define "oca-repository.fullname" -}}
oca-repository
{{- end }}

{{/*
Standard labels
*/}}
{{- define "oca-repository.labels" -}}
app.kubernetes.io/name: {{ include "oca-repository.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "oca-repository.selectorLabels" -}}
app.kubernetes.io/name: {{ include "oca-repository.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
