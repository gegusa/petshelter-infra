#!/usr/bin/env bash
# Демонстрация балансировки нагрузки
# Запуск: ./demo-lb.sh
# Переменные окружения для переопределения URL:
#   SHELTER_URL=https://shelter-for-pets.duckdns.org
#   CLINIC_URL=https://clinic-for-pets.duckdns.org

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
    local label="$2"
    local ok=0 fail=0
    for i in $(seq 1 "$REQUESTS"); do
        status=$(curl -sk -o /dev/null -w "%{http_code}" "$url")
        if [ "$status" = "200" ]; then
            echo "  [$i/$REQUESTS] $label → HTTP $status  OK"
            ok=$((ok + 1))
        else
            echo "  [$i/$REQUESTS] $label → HTTP $status  FAIL"
            fail=$((fail + 1))
        fi
        sleep 0.2
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

pause


divider "ШАГ 2 — Нормальная работа: $REQUESTS запросов к PetShelter"

echo "  СОВЕТ: откройте второй терминал и выполните:"
echo "    docker compose logs -f petshelter-api-1 petshelter-api-2"
echo "  Будет видно, что оба инстанса обрабатывают запросы."
echo

send_requests "$SHELTER_URL/api/animals" "PetShelter"

echo
echo "  Метрики по инстансам — запустите в браузере или curl:"
echo "    Prometheus: http://localhost:9090"
echo "    Запрос:     http_requests_received_total{job='petshelter-api'}"
echo "  Будут отдельные серии для petshelter-api-1:8080 и petshelter-api-2:8080."

pause


divider "ШАГ 3 — Отказ одного инстанса"

echo "  Останавливаем petshelter-api-2..."
docker compose stop petshelter-api-2
echo
echo "  Состояние после остановки:"
docker compose ps petshelter-api-1 petshelter-api-2
echo
echo "  Caddy обнаружит недоступность при следующей health-проверке (до 10 сек)"
echo "  и перестанет направлять запросы на упавший инстанс."

sleep 12
echo
echo "  Пауза 12 сек истекла — health-check сработал. Отправляем $REQUESTS запросов:"
echo

send_requests "$SHELTER_URL/api/animals" "PetShelter (1 инстанс)"

echo
echo "  Все запросы прошли через petshelter-api-1. Сервис продолжает работать."

pause


divider "ШАГ 4 — Восстановление инстанса"

echo "  Запускаем petshelter-api-2 снова..."
docker compose start petshelter-api-2
echo
echo "  Ожидание: Caddy вернёт инстанс в ротацию после успешного health-check (10 сек)..."
sleep 12
echo
echo "  Состояние после восстановления:"
docker compose ps petshelter-api-1 petshelter-api-2
echo
echo "  Отправляем $REQUESTS запросов — оба инстанса должны участвовать:"
echo

send_requests "$SHELTER_URL/api/animals" "PetShelter"

echo
echo "  Балансировка восстановлена. Проверьте в логах Caddy или Prometheus."

pause


divider "ШАГ 5 — То же самое для VetClinic"

echo "  Останавливаем vetclinic-api-2..."
docker compose stop vetclinic-api-2
sleep 12

echo "  Запросы к VetClinic при одном инстансе:"
send_requests "$CLINIC_URL/api/statistics" "VetClinic (1 инстанс)"

echo
echo "  Восстанавливаем vetclinic-api-2..."
docker compose start vetclinic-api-2
sleep 12

echo "  Запросы после восстановления:"
send_requests "$CLINIC_URL/api/statistics" "VetClinic"

pause


divider "ИТОГ"
echo "  Продемонстрировано:"
echo "  1. Два инстанса на каждый сервис работают параллельно"
echo "  2. Политика least_conn распределяет нагрузку по активным соединениям"
echo "  3. При отказе инстанса Caddy автоматически исключает его из ротации"
echo "  4. При восстановлении инстанс возвращается в ротацию без перезапуска системы"
echo
echo "  Логи Caddy (upstream для каждого запроса):"
echo "    docker compose logs caddy | jq -r '.upstream // empty' | sort | uniq -c"
echo
echo "  Метрики в Prometheus (количество запросов по инстансам):"
echo "    http://localhost:9090/graph"
echo "    Запрос: rate(http_requests_received_total{job='petshelter-api'}[1m])"
