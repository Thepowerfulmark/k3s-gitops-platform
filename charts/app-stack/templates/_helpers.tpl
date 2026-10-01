{{- define "app.labels" -}}
app.kubernetes.io/name: app-stack
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: app-stack
app.kubernetes.io/version: {{ .version | quote }}
{{- end }}

{{- define "app.selector" -}}
app.kubernetes.io/name: app-stack
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "app.backendImage" -}}
{{ .Values.backend.image.repository }}:{{ .Values.backend.image.tag }}
{{- end }}

{{- define "app.frontendImage" -}}
{{ .Values.frontend.image.repository }}:{{ .Values.frontend.image.tag }}
{{- end }}

{{- define "app.backendEnv" -}}
- name: PORT
  value: {{ .Values.backend.service.port | quote }}
- name: HEALTH_PATH
  value: {{ .Values.backend.healthPath | quote }}
- name: LIVE_PATH
  value: {{ .Values.backend.livePath | quote }}
- name: POSTGRES_HOST
  value: {{ printf "%s-postgres" .Release.Name | quote }}
- name: POSTGRES_PORT
  value: "5432"
- name: RABBITMQ_HOST
  value: {{ printf "%s-rabbitmq" .Release.Name | quote }}
- name: RABBITMQ_PORT
  value: "5672"
- name: RABBITMQ_HTTP_PORT
  value: "15672"
- name: QUEUE_NAME
  value: {{ .Values.backend.queue | quote }}
- name: HOME
  value: /tmp
- name: PYTHONDONTWRITEBYTECODE
  value: "1"
- name: PYTHONUNBUFFERED
  value: "1"
{{- range .Values.backend.secretEnv }}
- name: {{ .name | quote }}
  valueFrom:
    secretKeyRef:
      name: {{ $.Values.existingSecret | quote }}
      key: {{ .key | quote }}
{{- end }}
{{- end }}

{{- define "app.nginxConfig" }}
worker_processes 1;
error_log /tmp/error.log warn;
pid /tmp/nginx.pid;
events { worker_connections 128; }
http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  access_log /tmp/access.log;
  client_body_temp_path /tmp/client_body;
  proxy_temp_path /tmp/proxy;
  fastcgi_temp_path /tmp/fastcgi;
  uwsgi_temp_path /tmp/uwsgi;
  scgi_temp_path /tmp/scgi;
  server_tokens off;
  client_max_body_size 256k;
  server {
    listen {{ .Values.frontend.service.port }};
    server_name _;
    root /usr/share/nginx/html;
    resolver __NAMESERVER__ valid=5s ipv6=off;
    set $upstream {{ .Release.Name }}-backend:{{ .Values.backend.service.port }};
    location /api/ { proxy_pass http://$upstream; }
    location = {{ .Values.backend.healthPath }} { proxy_pass http://$upstream; }
    location = {{ .Values.backend.livePath }} { proxy_pass http://$upstream; }
    location / { try_files $uri /index.html; }
  }
}
{{ end }}
