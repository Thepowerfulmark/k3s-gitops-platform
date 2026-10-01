# Архитектура

Один узел k3s. В namespace `demo` чарт `charts/app-stack` поднимает frontend, backend, Postgres, RabbitMQ и Job миграции. Argo CD в namespace `argocd` синхронизирует этот чарт из git. Headlamp, DNS и StorageClass `local-path` живут в `kube-system`.

Диапазоны `10.42.0.0/16` и `10.43.0.0/16` на схемах — значения по умолчанию k3s для адресов подов и Service, не адрес стенда.

## Кластер

```mermaid
flowchart LR
  browser[Browser]
  subgraph node [k3s node]
    subgraph ks [namespace kube-system]
      dns[kube-dns]
      path[local-path]
      lamp[Headlamp]
    end
    subgraph gitops [namespace argocd]
      argo[Argo CD]
    end
    subgraph appns [namespace demo]
      feSvc[Service frontend NodePort]
      fe[Pod frontend]
      beSvc[Service backend]
      be[Pod backend]
      job[Job migrate]
      pgSvc[Service postgres]
      pg[Pod postgres]
      pgPvc[PVC postgres]
      mqSvc[Service rabbitmq]
      mq[Pod rabbitmq]
      mqPvc[PVC rabbitmq]
    end
  end
  browser --> feSvc --> fe --> beSvc --> be
  be --> pgSvc --> pg --> pgPvc
  be --> mqSvc --> mq --> mqPvc
  job --> pgSvc
  pgPvc --- path
  mqPvc --- path
  be --> dns
  argo --> appns
```

Frontend публикуется NodePort, потому что установщик k3s в `bootstrap/install-k3s.sh` выключает встроенный Traefik. Backend ходит в Postgres и в HTTP API брокера. Job `migrate` создаёт таблицу `items`. Оба PVC создаёт StorageClass `local-path` на диске этого узла.

Файлы: `charts/app-stack/templates/frontend.yaml`, `backend.yaml`, `postgres.yaml`, `rabbitmq.yaml`, `migrate.yaml`.

## GitOps

```mermaid
flowchart LR
  edit[Edit values.yaml] --> push[git push]
  push --> repo[GitHub main]
  repo --> argo[Argo CD]
  argo --> sync[sync]
  sync --> cluster[namespace demo]
  revert[git revert] --> push
```

`argocd/application.yaml` включает automated sync, selfHeal и prune. Ручная правка пода расходится с git, и selfHeal возвращает кластер к коммиту. Откат — `git revert` и push. История sync в UI Argo CD показывает прошлые применения, но при включённом selfHeal источник правды остаётся git.

## Сеть

```mermaid
flowchart TB
  admin[admin-cidr-here]
  world[other sources]
  fw[host chain PLATFORM-IN]
  fe[frontend]
  be[backend]
  pg[postgres]
  mq[rabbitmq]
  dns[kube-dns]
  admin -->|SSH API UI| fw
  world -->|80 and 443| fw
  fw --> fe
  fe --> be
  be --> pg
  be --> mq
  be --> dns
```

NetworkPolicy в чарте сначала запрещает весь трафик подов namespace, затем разрешает обмен внутри namespace, DNS в `kube-system` и вход на порт frontend. Поле `networkPolicy.frontendIngressCIDR` сужает этот вход; пустое значение оставляет `0.0.0.0/0`.

Скрипт `security/host-firewall.sh` ставит свою цепочку в начало INPUT. Порты 80 и 443 остаются открытыми. SSH, API Kubernetes и NodePort UI принимаются только из `ADMIN_CIDR`. Остальной трафик хоста цепочка не переписывает: последнее правило в ней RETURN. Таймер возвращает прежние правила, если цепочку не подтвердить. Чарт этот скрипт не запускает.

Пример тех же политик без Helm: `security/default-deny.yaml`.
