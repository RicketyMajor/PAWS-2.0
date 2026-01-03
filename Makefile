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