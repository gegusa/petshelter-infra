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

demo_failover() {
    local service="$1"
    local url="$2"
    local peer="$3"

    divider "Отказ $service"
    echo "  Останавливаем $service..."
    docker compose stop "$service"
    echo
    docker compose ps "$peer" "$service"
    echo
    echo "  Ожидание: Caddy обнаружит отказ при health-check (до 10 сек)..."
    sleep 12
    echo "  Отправляем $REQUESTS запросов — все должны уйти на $peer:"
    echo
    send_requests "$url"
    echo
    echo "  Все запросы обработаны единственным живым инстансом ($peer)."
    pause

    divider "Восстановление $service"
    echo "  Запускаем $service..."
    docker compose start "$service"
    echo
    echo "  Ожидание: Caddy вернёт инстанс в ротацию после успешного health-check (10 сек)..."
    sleep 12
    echo
    docker compose ps "$peer" "$service"
    echo
    echo "  Отправляем $REQUESTS запросов — нагрузка должна снова распределиться:"
    echo
    send_requests "$url"
    echo
    echo "  Оба инстанса снова в ротации."
    pause
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


demo_failover "petshelter-api-2" "$SHELTER_URL/api/animals"   "petshelter-api-1"
demo_failover "vetclinic-api-2"  "$CLINIC_URL/api/statistics" "vetclinic-api-1"


divider "ШАГ 8 — Проверка вручную (curl)"

echo "  Заголовок X-Served-By можно проверить в любой момент:"
echo
echo "    curl -sI $SHELTER_URL/api/animals | grep -i x-served-by"
echo "    curl -sI $CLINIC_URL/api/statistics | grep -i x-served-by"
echo
for url in "$SHELTER_URL/api/animals"    "$SHELTER_URL/api/animals" \
           "$CLINIC_URL/api/statistics"  "$CLINIC_URL/api/statistics"; do
    curl -sI "$url" | grep -i x-served-by || true
done

divider "Демонстрация завершена"
echo "  Метрики по инстансам в Prometheus:"
echo "    http://localhost:9090"
echo "    rate(http_requests_received_total{job=\"petshelter-api\"}[1m])"
echo "    rate(http_requests_received_total{job=\"vetclinic-api\"}[1m])"
