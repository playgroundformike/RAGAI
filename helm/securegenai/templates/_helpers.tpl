{{/*
============================================================
Helm Template Helpers
============================================================
These are reusable template snippets used across all templates.
They follow the DRY principle — define labels, names, and
selectors once, use them everywhere.

Why helpers matter:
- Consistent labels across all resources
- One place to change naming conventions
- Prevents label mismatches (e.g., deployment selector
  not matching service selector = traffic doesn't route)
============================================================
*/}}

{{/*
Chart name — used as the base for all resource names.
*/}}
{{- define "securegenai.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name — includes release name for uniqueness.
If release name contains chart name, don't duplicate it.
Truncate to 63 chars (Kubernetes name length limit).
*/}}
{{- define "securegenai.fullname" -}}
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
Common labels applied to ALL resources.
These labels enable:
- Filtering resources by app (kubectl get all -l app.kubernetes.io/name=securegenai)
- Helm release tracking (which release manages this resource)
- Version tracking (which chart/app version is deployed)
*/}}
{{- define "securegenai.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "securegenai.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app: {{ include "securegenai.name" . }}
{{- end }}

{{/*
Selector labels — used by Deployments, Services, and NetworkPolicies
to find the pods they manage. These MUST match across all resources
or traffic won't route and scaling won't work.
*/}}
{{- define "securegenai.selectorLabels" -}}
app.kubernetes.io/name: {{ include "securegenai.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "securegenai.name" . }}
{{- end }}

{{/*
Service account name — returns the configured name or the fullname default.
*/}}
{{- define "securegenai.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- include "securegenai.fullname" . }}
{{- end }}
{{- end }}
