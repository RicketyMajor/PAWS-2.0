# Makefile para PAWS 2.0

# 1. Levantar túneles a Kubernetes (Redis, RabbitMQ, MinIO) en segundo plano
tunnel:
	@echo "Estableciendo puentes a Kubernetes..."
	@kubectl port-forward svc/redis-service 6379:6379 > /dev/null 2>&1 &
	@kubectl port-forward svc/rabbitmq-service 5672:5672 > /dev/null 2>&1 &
	@kubectl port-forward svc/minio-service 9000:9000 > /dev/null 2>&1 &
	@echo "Puentes listos. Esperando estabilización..."
	@sleep 3

# 2. Matar túneles viejos (por si se quedan colgados)
clean-tunnel:
	@echo "Limpiando puertos..."
	@-pkill -f "kubectl port-forward" || true

# 3. Correr el Backend (incluye limpieza y levantado de túneles)
dev: clean-tunnel tunnel
	@echo "Iniciando Backend PAWS..."
	@go run cmd/api/main.go

# 4. Recorrido E2E contra el despliegue. Necesita dos JWT guardados en archivos:
#      read -rsp "Contraseña: " P; echo
#      curl -s -X POST $$API/auth/login -H "Content-Type: application/json" \
#        -d "{\"email\":\"...\",\"password\":\"$$P\"}" | jq -r .token > ~/.paws_tok_a; unset P
TOK_A ?= ~/.paws_tok_a
TOK_B ?= ~/.paws_tok_b
N ?= 8

# Recorrido completo: publica, desliza, acepta, chatea y lee el historial.
e2e:
	@python3 scripts/e2e.py --token-a $(TOK_A) --token-b $(TOK_B)

# Siembra N mascotas para que el mazo no esté vacío. Solo necesita la cuenta rescatista.
seed:
	@python3 scripts/e2e.py --token-a $(TOK_A) --seed $(N)

# =========================================================================
# 5. Entorno de pruebas local, completo y sin intervención manual
# =========================================================================
#
# El stack local corre con EMAIL_SIMULATION=true, así que el OTP nunca sale de la
# máquina: se escribe en Redis y el arnés lo lee de ahí. Por eso `local-bootstrap`
# puede crear las dos cuentas por la API real —mismos endpoints, misma validación,
# mismo bcrypt— sin buzón y sin que nadie teclee una contraseña.
#
# Nada de esto toca producción: docker-compose.yml fija DATABASE_URL y REDIS_URL a
# los contenedores locales y NO los interpola desde .env, que apunta a Supabase y
# Upstash.

LOCAL_API ?= http://localhost:8080/api/v1
LOCAL_WS  ?= ws://localhost:8080/api/v1/ws
LOCAL_TOK_A ?= .local-tokens/tok_a
LOCAL_TOK_B ?= .local-tokens/tok_b

# Levanta el stack y espera a que responda de verdad, no a que el contenedor exista.
local-up:
	@docker compose up -d --build --wait
	@echo "Esperando al backend..."
	@for i in $$(seq 1 30); do \
		curl -sf $(LOCAL_API)/health >/dev/null && echo "  backend arriba en $(LOCAL_API)" && exit 0; \
		sleep 2; \
	done; \
	echo "  el backend no respondió en 60 s:"; docker compose logs --tail 30 backend; exit 1

# Baja el stack y BORRA los volúmenes: cada corrida parte de una base limpia.
local-down:
	@docker compose down -v
	@rm -rf .local-tokens

# Crea las dos cuentas y deja sus tokens en .local-tokens/
local-bootstrap:
	@mkdir -p .local-tokens
	@python3 scripts/e2e.py --api $(LOCAL_API) --bootstrap \
		--token-a $(LOCAL_TOK_A) --token-b $(LOCAL_TOK_B)

# El recorrido entero contra el stack local.
local-e2e:
	@python3 scripts/e2e.py --api $(LOCAL_API) --ws $(LOCAL_WS) \
		--token-a $(LOCAL_TOK_A) --token-b $(LOCAL_TOK_B)

# Siembra N mascotas en el mazo local.
local-seed:
	@python3 scripts/e2e.py --api $(LOCAL_API) --token-a $(LOCAL_TOK_A) --seed $(N)

# Un solo comando: base limpia, cuentas nuevas, mazo sembrado y recorrido completo.
local-test: local-down local-up local-bootstrap local-seed local-e2e

.PHONY: tunnel clean-tunnel dev e2e seed local-up local-down local-bootstrap local-e2e local-seed local-test
