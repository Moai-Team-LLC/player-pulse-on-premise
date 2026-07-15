# Player Pulse — Руководство по установке On-Premise

Это руководство проведёт вас через установку Player Pulse на собственном
сервере — от чистой Linux-машины до полностью работающей, доступной извне
CRM-системы.

---

## 1. Обзор

Player Pulse работает как набор Docker-контейнеров на вашем сервере:

| Сервис                       | Что делает                                                            |
|------------------------------|-----------------------------------------------------------------------|
| `api`                        | Основной бэкенд CRM                                                   |
| `connector`                  | API для передачи данных игроков из вашей игровой платформы/интеграций |
| `frontend`                   | Веб-интерфейс CRM для вашей команды                                   |
| `superadmin`                 | Панель администратора для управления тенантами и пользователями       |
| `outbox_worker`              | Фоновый воркер для асинхронной отправки email/событий                 |
| `postgres`, `redis`, `minio` | База данных, кэш и файловое хранилище                                 |

Все образы Docker публичные и собраны заранее — для их загрузки не нужны
никакие учётные данные. Единственное, что ограничивает доступ — это ваш
**лицензионный ключ**, который вы получаете при подписании контракта.

---

## 2. Требования

- Linux-сервер (рекомендуется Ubuntu/Debian) с доступом root или sudo
- Установленные **Docker** и **Docker Compose v2**
- Установленные `openssl` и `curl` (используются установочным скриптом)
- Три домена (или поддомена), указывающих на IP вашего сервера:
    - Один для основной CRM (например, `crm.yourcompany.com`)
    - Один для панели супер-администратора (например, `admin.yourcompany.com`)
    - Один для API коннектора, если вы будете интегрировать внешние системы (например, `connector.yourcompany.com`)
- Ваш **лицензионный ключ** (высылается отдельно, при подписании контракта)
- Способ отправки email — либо аккаунт Mailgun, либо SMTP-данные от любого
  провайдера (собственный почтовый сервер, Amazon SES, SendGrid, Postmark и т.д.)

Вам **не** нужен никакой аккаунт GitHub, токен или какие-либо учётные данные
для загрузки Docker-образов или клонирования этого репозитория — всё
публично.

---

## 3. Получение файлов

```bash
git clone https://github.com/Moai-Team-LLC/player-pulse-on-premise.git
cd player-pulse-on-premise
chmod +x install.sh update.sh
```

---

## 4. Запуск установщика

Запустите установщик и ответьте на вопросы:

```bash
./install.sh
```

Вас спросят:

| Вопрос                                           | Что вводить                                                                                                      |
|--------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| Домен для основной CRM                           | например, `crm.yourcompany.com`                                                                                  |
| Домен для панели супер-администратора            | например, `admin.yourcompany.com`                                                                                |
| Лицензионный ключ                                | Предоставляется при подписании контракта                                                                         |
| Провайдер почты                                  | `mailgun` или `smtp`                                                                                             |
| *(если mailgun)* домен Mailgun, API-ключ, регион | Из вашей панели Mailgun — регион `us` или `eu`, уточните какой используется в вашем аккаунте                     |
| *(если smtp)* хост, порт, логин, пароль SMTP     | От вашего почтового провайдера                                                                                   |
| Email отправителя                                | Адрес "от кого", который будет использоваться в письмах сброса пароля/приглашений                                |
| Email для первого аккаунта супер-администратора  | Это будет ваш первый логин                                                                                       |
| Публичный URL MinIO (опционально)                | Нужен только если хотите, чтобы загруженные файлы были доступны напрямую из браузера; пока можно оставить пустым |

Далее скрипт:

1. Автоматически генерирует все внутренние секреты (пароль БД, ключи подписи, ключи шифрования)
2. Загружает Docker-образы
3. Запускает все сервисы
4. Дожидается, пока API сообщит о готовности
5. Выводит ваши данные для входа и дальнейшие шаги

Если установка прервётся на середине, **не запускайте скрипт заново с нуля**
— секреты уже сгенерированы и сохранены. Вместо этого запустите
`./install.sh --resume` — он продолжит с того места, где остановился, не
перегенерируя ничего.

Автоматизированная установка (без интерактивных вопросов) также
поддерживается — передайте нужные значения флагами, и скрипт не будет их
запрашивать. Полный список (доступен в любой момент командой
`./install.sh --help`):

```
Usage: ./install.sh [flags]

Runs interactively by default, prompting for anything not passed as a flag.
Pass all required flags to run fully non-interactively.

  --domain=...                   Domain for the main CRM
  --super-admin-domain=...       Domain for the super admin panel
  --license=...                  License key (provided at contract signing)

  --mail-provider=mailgun|smtp   Which mail provider to use

  --mailgun-domain=...           Mailgun domain
  --mailgun-api-key=...          Mailgun API key
  --mailgun-region=us|eu         Mailgun account region — check your Mailgun dashboard

  --smtp-host=...                SMTP server host
  --smtp-port=...                SMTP server port (defaults to 587 if left blank interactively)
  --smtp-username=...            SMTP username
  --smtp-password=...            SMTP password

  --mail-sender=...              Sender email, e.g. "Your Company <noreply@yourcompany.com>"
  --cors-origins=...             Optional, derived from the two domains above if omitted
  --s3-public-url=...            Optional, only needed for public file URLs
  --super-admin-email=...        Email for the initial super admin account

  --resume                       Reuse an existing .env instead of generating a new one
                                  (use this to retry after a failed first-time install)

  --help, -h                     Show this message and exit
```

Пример полностью неинтерактивной установки:

```bash
./install.sh --domain=crm.yourcompany.com --super-admin-domain=admin.yourcompany.com \
  --license=<ваша-лицензия> --mail-provider=smtp --smtp-host=... --smtp-port=587 \
  --smtp-username=... --smtp-password=... --mail-sender="Your Company <noreply@yourcompany.com>" \
  --super-admin-email=you@yourcompany.com
```

---

## 5. Критически важные шаги после установки

Установщик выводит их в конце — не пропускайте их.

### Немедленно сохраните ключ шифрования PII

В выводе установщика будет строка вида:

```
PII_MASTER_KEY=<длинная шестнадцатеричная строка>
```

Этот ключ шифрует все персональные данные игроков. **Если он будет утерян,
эти данные невозможно будет восстановить — ни вам, ни нам.** Скопируйте его
сейчас же в надёжное место вне этого сервера (менеджер паролей, хранилище
секретов — куда угодно, лишь бы надёжно).

### Сохраните файл `.env`

Он содержит все секреты вашей установки. Сохраните копию в надёжном месте
вне самого сервера.

### Смените начальный пароль супер-администратора

Войдите с данными, выведенными в конце установки, и сразу же смените пароль.

---

## 6. Настройка реверс-прокси

Это **ваша зона ответственности** — Player Pulse не включает и не управляет
реверс-прокси за вас. Без него ваши домены не смогут достучаться до
запущенных контейнеров, и у вас не будет HTTPS.

Ниже — рабочая конфигурация `nginx`. Самая важная деталь: **у каждого блока
`location` должны быть свои собственные строки `proxy_set_header`** — nginx
не наследует их между соседними `location`-блоками, и отсутствие этих строк
— самая частая причина неработающей установки (она ломает маршрутизацию по
доменам/тенантам таким образом, что выглядит как случайная ошибка 404).

```nginx
server {
    listen 80;
    server_name crm.yourcompany.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/v1 {
        client_max_body_size 75M;
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name admin.yourcompany.com;

    location / {
        proxy_pass http://localhost:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/v1 {
        client_max_body_size 75M;
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name connector.yourcompany.com;

    location / {
        client_max_body_size 75M;
        proxy_pass http://localhost:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Скорректируйте порты `proxy_pass`, если вы меняли `API_PORT`/`FRONTEND_PORT`/
`SUPERADMIN_PORT`/`CONNECTOR_PORT` относительно значений по умолчанию в
`.env`.

**Для HTTPS** проще всего использовать [certbot](https://certbot.eff.org/) с
плагином nginx:

```bash
sudo certbot --nginx -d crm.yourcompany.com -d admin.yourcompany.com -d connector.yourcompany.com
```

### Настройте `TRUSTED_PROXIES`

После того как реверс-прокси запущен, найдите gateway-адрес Docker-сети —
именно с этого адреса nginx на самом деле подключается, с точки зрения
контейнера:

```bash
docker network ls | grep player-pulse
docker network inspect <имя-сети-из-предыдущей-команды> | grep -A3 '"Gateway"'
```

Добавьте этот адрес в `.env`:

```
TRUSTED_PROXIES=<gateway-адрес>/32
```

Затем перезапустите затронутые сервисы:

```bash
docker compose -f docker-compose.on-premise.yml up -d --force-recreate api connector
```

Без этого шага в журналах аудита и логах входа будет отображаться IP-адрес
прокси, а не реальный IP-адрес ваших пользователей.

---

## 7. Первый вход

Перейдите на домен супер-администратора (например,
`https://admin.yourcompany.com`) и войдите с данными, которые вывел
установщик.

**Первый вход с нового устройства/IP запрашивает код подтверждения**,
отправленный на вашу почту — это ожидаемое поведение системы безопасности, а
не ошибка. Введите 6-значный код, когда система его запросит.

---

## 8. Создание тенантов и пользователей

Каждый "тенант" в Player Pulse представляет отдельный бренд/операцию со
своими изолированными данными игроков. В панели супер-администратора:

1. Создайте тенант — укажите название и домен (подойдёт и поддомен вашего
   собственного домена, например `royal.yourcompany.com`, если он также
   указывает на ваш сервер и для него настроен соответствующий блок nginx).
2. Пригласите первого администратора тенанта по email.
3. Этот человек принимает приглашение (ссылка приходит на почту),
   устанавливает пароль и входит в систему на домене своего тенанта — далее
   он самостоятельно управляет своей командой, брендингом и всем остальным.

Вам (владельцу установки) нужно сделать это только один раз на каждый
тенант — дальнейшее повседневное управление полностью самообслуживаемо со
стороны администратора этого тенанта.

---

## 9. Обновление

Когда выходит новая версия, обновляйтесь командой:

```bash
./update.sh <версия>
```

Например:

```bash
./update.sh 1.1.0
```

Скрипт скачивает compose-файл новой версии, делает резервную копию текущего,
загружает новые образы и перезапускает всё. Ваши данные при этом не
затрагиваются — заменяются только контейнеры приложения, база данных и файлы
остаются как есть.

**Откат**: если что-то пошло не так, запустите `./update.sh` снова с номером
предыдущей версии, чтобы вернуться назад.

---

## 10. Устранение неполадок

**«API did not become healthy in time» при установке/обновлении**
Проверьте фактическую ошибку:

```bash
docker compose -f docker-compose.on-premise.yml logs api
```

Частые причины: неверный лицензионный ключ, проблема подключения к базе
данных, или конфликт портов с чем-то ещё, уже запущенным на сервере.

**Конкретный домен возвращает 404 или ведёт не туда**
Почти всегда это неправильная настройка реверс-прокси — проверьте, что у
каждого блока `location` есть свои собственные строки `proxy_set_header`
(см. раздел 6).

**Строка в логах вида `[license] WARNING: license expired - N day(s) left in grace period, renew immediately`**
Это ожидаемое поведение, а не ошибка. Ваша лицензия имеет фиксированный
срок действия; после его истечения приложение продолжает работать ещё 14
дней (льготный период), чтобы у вас было время на продление, ежедневно
выводя это предупреждение в логи. Свяжитесь с нами для продления до
окончания льготного периода — после этого приложение откажется
запускаться (`license expired and grace period has ended`) до тех пор,
пока не будет установлен новый лицензионный ключ.

---

## 11. Поддержка

Свяжитесь с нами напрямую за помощью по установке, чтобы сообщить о
проблеме или запросить новую лицензию/версию. Контакты поддержки были
предоставлены при подписании контракта.