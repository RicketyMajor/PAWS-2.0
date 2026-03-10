# -------------------
# Stage 1: Builder
# -------------------
# This stage compiles the Go application.
FROM golang:alpine AS builder

WORKDIR /app

# Copy dependency files and download dependencies.
# This is done first to leverage Docker layer caching.
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the source code.
COPY . .

# Build the Go binary.
RUN go build -o main ./cmd/api


# -------------------
# Stage 2: Runner
# -------------------
# This stage creates the final, lightweight production image.
FROM alpine:latest

WORKDIR /app

# Copy only the compiled binary from the builder stage.
COPY --from=builder /app/main .

# Expose the port the application runs on.
EXPOSE 8080

# The command to run the application.
CMD ["./main"]