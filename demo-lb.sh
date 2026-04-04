#!/usr/bin/env bash

set -euo pipefail

SHELTER_URL="${SHELTER_URL:-https://shelter-for-pets.duckdns.org}"
CLINIC_URL="${CLINIC_URL:-https://clinic-for-pets.duckdns.org}"
REQUESTS=12

# ─────────────────────────────────────────────
divider() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

pause() {
    echo
    read -rp "  >>> Нажмите Enter для следующего шага..."
    echo
}

# Отправляет запросы и показывает какой инстанс ответил (через заголовок X-Served-By)
send_requests() {
    local url="$1"
    local ok=0 fail=0
    for i in $(seq 1 "$REQUESTS"); do
        headers=$(curl -sk -D - -o /dev/null "$url")
        status=$(echo "$headers" | awk 'NR==1{print $2}' | tr -d '\r')
        served_by=$(echo "$headers" | grep -i "x-served-by:" | tr -d '\r' | awk '{print $2}')
        if [ "$status" = "200" ]; then
            echo "  [$i/$REQUESTS] HTTP $status  ← ${served_by:-unknown}"
            ok=$((ok + 1))
        else
            echo "  [$i/$REQUESTS] HTTP $status  FAIL"
            fail=$((fail + 1))
        fi
        sleep 0.3
    done
    echo
    echo "  Итог: успешных=$ok  ошибок=$fail"
}
# ─────────────────────────────────────────────


divider "ШАГ 1 — Состояние инстансов"

echo "  Запущенные контейнеры сервисов:"
echo
docker compose ps \
    petshelter-api-1 petshelter-api-2 \
    vetclinic-api-1  vetclinic-api-2
echo
echo "  Caddy проверяет здоровье каждого инстанса каждые 10 сек (GET /metrics)."
echo "  Политика балансировки: least_conn — запрос идёт к наименее загруженному."
echo "  Каждый ответ несёт заголовок X-Served-By с адресом обработавшего инстанса."

pause


divider "ШАГ 2 — Нормальная работа: $REQUESTS запросов к PetShelter"

send_requests "$SHELTER_URL/api/animals"
echo
echo "  Запросы распределяются между обоими инстансами."

pause


divider "ШАГ 3 — Нормальная работа: $REQUESTS запросов к VetClinic"

send_requests "$CLINIC_URL/api/statistics"
echo
echo "  Аналогично для VetClinic."

pause


divider "ШАГ 4 — Отказ инстанса petshelter-api-2"

echo "  Останавливаем petshelter-api-2..."
docker compose stop petshelter-api-2
echo
docker compose ps petshelter-api-1 petshelter-api-2
echo
echo "  Ожидание: Caddy обнаружит отказ при health-check (до 10 сек)..."
sleep 12
echo
echo "  Отправляем $REQUESTS запросов:"
echo

send_requests "$SHELTER_URL/api/animals"
echo
echo "  Все запросы идут только через petshelter-api-1."

pause


divider "ШАГ 5 — Восстановление petshelter-api-2"

echo "  Запускаем petshelter-api-2..."
docker compose start petshelter-api-2
echo
echo "  Ожидание: Caddy вернёт инстанс в ротацию после успешного health-check (10 сек)..."
sleep 12
echo
docker compose ps petshelter-api-1 petshelter-api-2
echo
echo "  Отправляем $REQUESTS запросов:"
echo

send_requests "$SHELTER_URL/api/animals"
echo
echo "  Нагрузка снова распределена между двумя инстансами."

pause


divider "ШАГ 6 — Проверка вручную (curl)"

echo "  Можно также проверить заголовок вручную:"
echo
echo "    curl -sI $SHELTER_URL/api/animals | grep x-served-by"
echo
curl -sI "$SHELTER_URL/api/animals" | grep -i x-served-by || true
curl -sI "$SHELTER_URL/api/animals" | grep -i x-served-by || true
curl -sI "$SHELTER_URL/api/animals" | grep -i x-served-by || true
curl -sI "$SHELTER_URL/api/animals" | grep -i x-served-by || true

divider "Демонстрация завершена"
echo "  Метрики по инстансам в Prometheus:"
echo "    http://localhost:9090"
echo "    rate(http_requests_received_total{job=\"petshelter-api\"}[1m])"
