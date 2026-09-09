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

.PHONY: tunnel clean-tunnel dev e2e seed
