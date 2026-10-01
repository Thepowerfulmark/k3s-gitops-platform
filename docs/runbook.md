# Установка платформы

Все шаги ниже выполняются от `root` на узле, который будет кластером.

Разработка и тестирование проводились на Debian 13. Другие дистрибутивы этим документом отдельно не покрываются.

Секреты в текст не входят. Пароли берите из защищённого хранилища и подставляйте вместо `replace-from-vault`. Адреса в примерах — `node-ip-here`, `admin-cidr-here`, `example.com`.

## 1. Введение

Ставится одноузловой k3s, Helm, Argo CD, панель Headlamp и приложение из чарта `charts/app-stack`: frontend, backend, Postgres, RabbitMQ и Job миграции. Желаемое состояние кластера хранится в git. Argo CD применяет чарт в namespace `demo`.

Пароли в git не кладутся. Их создают в Secret кластера до синхронизации.

## 2. Состав и layout

| Namespace | Что внутри |
|---|---|
| `demo` | релиз чарта: frontend, backend, Postgres, RabbitMQ, Job миграции |
| `argocd` | Argo CD |
| `kube-system` | DNS, StorageClass `local-path`, Headlamp |

| Объект | Вид | Порт |
|---|---|---|
| frontend | Deployment, Service NodePort `30080` | `8080` |
| backend | Deployment, Service внутри namespace | `8080` |
| postgres | StatefulSet, PVC `1Gi` | `5432` |
| rabbitmq | StatefulSet, PVC `1Gi` | `5672`, HTTP API `15672` |
| migrate | Job | — |

Чарт лежит в `charts/app-stack`. Манифест Application — `argocd/application.yaml`, проект — `argocd/project.yaml`. Скрипты установки — `bootstrap/`.

Один релиз на namespace. Имена Service собираются из имени релиза: у релиза `demo` backend доступен как `demo-backend`.

## 3. Зависимости

Разработка и тестирование проводились на k3s `v1.36.4+k3s1`, Helm `v3.22.0`, Argo CD `v2.13.3`.

На узле нужен `curl` и исходящий доступ в интернет на время установки k3s, загрузки образов и чтения git. Свободного места должно хватить на два тома по `1Gi` и на образы.

Postgres и брокер приходят контейнерами чарта. Отдельные пакеты базы и брокера на хост не ставятся.

Если на хосте уже запущен Docker, его сеть не должна пересекаться с pod CIDR и service CIDR k3s. Значения по умолчанию k3s: `10.42.0.0/16` и `10.43.0.0/16`.

## 4. Установка k3s

На новом узле:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.4+k3s1 sh -s - server \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 600
```

Те же флаги выполняет `bash bootstrap/install-k3s.sh`. Если k3s уже установлен, скрипт печатает версию и не перезапускает службу.

Traefik и ServiceLB выключены: вход в приложение идёт через NodePort.

Проверка:

```bash
k3s kubectl get nodes
```

В колонке `STATUS` должно быть `Ready`. Kubeconfig на узле: `/etc/rancher/k3s/k3s.yaml`, режим `600`.

Дальше в этом документе команды идут через `k3s kubectl`.

## 5. Установка Argo CD

```bash
bash bootstrap/install-helm.sh
bash bootstrap/install-argocd.sh
```

`install-helm.sh` кладёт Helm `v3.22.0` в `/usr/local/bin/helm`.

`install-argocd.sh` на новом кластере выполняет:

```bash
k3s kubectl create namespace argocd --dry-run=client -o yaml | k3s kubectl apply -f -
k3s kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.3/manifests/install.yaml
k3s kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
k3s kubectl -n argocd patch svc argocd-server --type strategic \
  -p '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30081}]}}'
```

Если Argo CD уже стоит, скрипт печатает образ и не применяет манифест повторно.

Пароль первичной учётной записи `admin` читается из Secret кластера:

```bash
k3s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
```

Откройте `http://node-ip-here:30081` (или `http://example.com:30081`, если имя указывает на узел), войдите и смените пароль в UI.

Headlamp:

```bash
bash bootstrap/install-headlamp.sh
```

Скрипт применяет `bootstrap/headlamp.yaml`: ServiceAccount `headlamp` связан с `cluster-admin`, Service слушает NodePort `30082`, образ `ghcr.io/headlamp-k8s/headlamp:v0.45.0`. Если Deployment уже есть, скрипт его не меняет.

Токен на 8 часов:

```bash
k3s kubectl -n kube-system create token headlamp --duration=8h
```

Откройте `http://node-ip-here:30082` и вставьте токен. На общем кластере роль `cluster-admin` сужают.

## 6. Секреты

Namespace и Secret создаются до Application. Значения не записывайте в файл values.

```bash
k3s kubectl create namespace demo
k3s kubectl -n demo create secret generic app-credentials \
  --from-literal=postgres-user=app \
  --from-literal=postgres-password=replace-from-vault \
  --from-literal=postgres-database=app \
  --from-literal=rabbitmq-user=app \
  --from-literal=rabbitmq-password=replace-from-vault \
  --from-literal=rabbitmq-vhost=app
```

Ключи Secret: `postgres-user`, `postgres-password`, `postgres-database`, `rabbitmq-user`, `rabbitmq-password`, `rabbitmq-vhost`.

Имя Secret и соответствие ключей переменным backend задаются в `charts/app-stack/values.yaml` полями `existingSecret` и `backend.secretEnv`. Полный текст values в этот документ не копируется.

## 7. Деплой приложения через Argo CD

Перед применением можно нарисовать манифесты, не отправляя их в кластер:

```bash
helm template demo charts/app-stack --namespace demo
```

Проект применяется раньше Application:

```bash
k3s kubectl apply -f argocd/project.yaml
k3s kubectl apply -f argocd/application.yaml
```

`argocd/application.yaml` смотрит на `https://github.com/Thepowerfulmark/k3s-gitops-platform.git`, путь `charts/app-stack`, namespace `demo`, sync автоматический, с selfHeal и prune.

Критичные поля values, если подставляется свой образ:

- `backend.image.repository`
- `backend.image.tag`
- `backend.service.port`
- `backend.healthPath`
- `backend.secretEnv`
- `frontend.image.repository`
- `frontend.image.tag`
- `frontend.service.nodePort`
- `existingSecret`
- `networkPolicy.frontendIngressCIDR`

Список переменных, которые чарт читает из Secret, — в `backend.secretEnv`. Хосты `POSTGRES_HOST` и `RABBITMQ_HOST` чарт ставит сам, по имени релиза.

Откройте UI Argo CD: Application `demo` должно быть Synced и Healthy. UI приложения: `http://node-ip-here:30080`.

## 8. Обновление и откат

Обновление образа — смена тега в `charts/app-stack/values.yaml` и push в `main`. Не перезаписывайте уже выпущенный тег: поставьте новый.

```bash
git add charts/app-stack/values.yaml
git commit -m "Publish image 0.1.1"
git push origin main
```

Argo CD подхватывает коммит. В UI Application снова Synced и Healthy.

Откат делается в git. При включённом selfHeal откат только кнопкой в UI будет затёрт следующим sync.

```bash
git revert HEAD
git push origin main
```

Job миграции назван с тегом образа. Пока тег тот же, завершённый Job не запускается снова. Повторный запуск после неудачи: удалите Job в UI, selfHeal создаст его заново. SQL миграции повторно безопасен.

Образ в GHCR: push в `main` публикует тег `sha-<commit>`. Git-тег `vX.Y.Z` публикует образ `X.Y.Z`. В values пишется образ без префикса `v`, то есть `0.1.0` для тега `v0.1.0`.

## 9. Изоляция сети

Чарт включает NetworkPolicy: сначала запрет всего трафика подов namespace, затем разрешение внутри namespace, DNS в `kube-system` и вход на порт frontend. Текст правил — `charts/app-stack/templates/networkpolicy.yaml`. Отдельный пример тех же правил — `security/default-deny.yaml`.

Пустой `networkPolicy.frontendIngressCIDR` означает источник `0.0.0.0/0` только для порта frontend. Чтобы сузить вход, запишите в values свой CIDR.

Файрвол хоста чарт не включает. Скрипт `security/host-firewall.sh` ставит цепочку `PLATFORM-IN` в начало INPUT и запускает таймер отката. Значения по умолчанию для адресов k3s: pod CIDR `10.42.0.0/16`, service CIDR `10.43.0.0/16`.

На узле, который можно закрыть:

```bash
install -m 0755 security/host-firewall.sh /usr/local/sbin/k3s-gitops-firewall.sh
ADMIN_CIDR=admin-cidr-here /usr/local/sbin/k3s-gitops-firewall.sh apply
```

`admin-cidr-here` замените на сеть администратора до запуска. Скрипт отвергает эту заглушку и `0.0.0.0/0`.

Держите текущую SSH-сессию открытой. С второго входа из той же сети проверьте SSH, API `6443` и UI. Если второй вход живой:

```bash
/usr/local/sbin/k3s-gitops-firewall.sh commit
```

Если нет — дождитесь таймера (по умолчанию 300 секунд) или выполните:

```bash
/usr/local/sbin/k3s-gitops-firewall.sh rollback
```

Цепочка пропускает 80 и 443 всем, а SSH, API и NodePort `30080`, `30081`, `30082` — только из `ADMIN_CIDR`. Прочий трафик хоста не режется: в конце цепочки RETURN. Скрипт меняет IPv4 iptables.

## 10 Проверка

- Откройте приложение: `http://node-ip-here:30080` или `http://example.com:30080`. Страница Items открывается, форма сохраняет запись.
- Откройте Argo CD: `http://node-ip-here:30081`. Application `demo` в состоянии Synced и Healthy.
- Откройте Headlamp: `http://node-ip-here:30082`. В namespace `demo` поды frontend, backend, postgres и rabbitmq видны, Job миграции завершён.

## 11. Удаление

Снять приложение, не трогая остальной кластер:

```bash
k3s kubectl -n argocd delete application demo
k3s kubectl -n argocd delete appproject app-stack
k3s kubectl delete namespace demo
```

Снять цепочку файрвола, если её подтверждали:

```bash
/usr/local/sbin/k3s-gitops-firewall.sh remove
```

Снять k3s целиком только на узле, который занят этим шаблоном и больше ничем:

```bash
/usr/local/bin/k3s-uninstall.sh
```
