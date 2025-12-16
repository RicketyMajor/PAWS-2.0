# ETAPA 1: Builder (Compilación)
# Usamos una imagen con Go instalado para compilar
FROM golang:alpine AS builder
# Instalamos herramientas necesarias
WORKDIR /app

# Copiamos los archivos de dependencias primero (para aprovechar caché de Docker)
COPY go.mod go.sum ./
RUN go mod download

# Copiamos el código fuente
COPY . .

# Compilamos el binario
# -o main: nombre del output
# ./cmd/api: ruta de tu main.go
RUN go build -o main ./cmd/api

# ETAPA 2: Runner (Ejecución)
# Usamos una imagen vacía y ligera de Alpine
FROM alpine:latest

WORKDIR /app

# Copiamos solo el binario compilado desde la etapa anterior
COPY --from=builder /app/main .

# Copiamos el archivo .env (opcional, pero útil si no pasamos todo por compose)
# COPY .env . 

# Exponemos el puerto
EXPOSE 8080

# Comando para iniciar
CMD ["./main"]