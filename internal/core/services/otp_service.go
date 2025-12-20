package services

import (
	"context"
	"fmt"
	"math/rand"
	"time"
	"log"

	"github.com/redis/go-redis/v9"
)

type OTPService struct {
	redisClient *redis.Client
}

func NewOTPService() *OTPService {
	// Configuración para Kubernetes (nombre del servicio: redis-service)
	// Si fallara localmente, intentaría localhost
	rdb := redis.NewClient(&redis.Options{
		Addr:     "redis-service:6379", // Nombre DNS interno en K8s
		Password: "", // Sin contraseña por ahora
		DB:       0,  // DB por defecto
	})

	return &OTPService{
		redisClient: rdb,
	}
}

// GenerateOTP crea un código, lo guarda en Redis (TTL 5 min) y simula el envío
func (s *OTPService) GenerateOTP(email string) (string, error) {
	// 1. Generar código de 6 dígitos
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	code := fmt.Sprintf("%06d", rng.Intn(1000000))

	// 2. Guardar en Redis con expiración (Distribuido)
	ctx := context.Background()
	key := fmt.Sprintf("otp:%s", email)
	
	// SetNX = Set if Not Exists (aunque aquí usaremos Set normal para sobrescribir si pide otro)
	err := s.redisClient.Set(ctx, key, code, 5*time.Minute).Err()
	if err != nil {
		return "", fmt.Errorf("error guardando OTP en Redis: %v", err)
	}

	// 3. Simular Envío de Correo (Aquí iría la llamada SMTP)
	// Para desarrollo, lo imprimimos en logs para que puedas copiarlo
	log.Printf("[SIMULACIÓN EMAIL] Para: %s | Código: %s", email, code)

	return code, nil
}

// VerifyOTP consulta Redis para validar el código
func (s *OTPService) VerifyOTP(email, inputCode string) bool {
	ctx := context.Background()
	key := fmt.Sprintf("otp:%s", email)

	// 1. Obtener el código real
	val, err := s.redisClient.Get(ctx, key).Result()
	if err == redis.Nil {
		return false // No existe o expiró
	} else if err != nil {
		log.Println("Error consultando Redis:", err)
		return false
	}

	// 2. Comparar
	if val == inputCode {
		// Opcional: Borrar el código tras uso exitoso (One-Time real)
		s.redisClient.Del(ctx, key)
		return true
	}

	return false
}