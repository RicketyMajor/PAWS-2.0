package middleware

import (
	"fmt"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// AuthMiddleware verifica que la petición tenga un token válido
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 1. Obtener el header "Authorization"
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "se requiere token de autorización"})
			return
		}

		// 2. El formato debe ser "Bearer <token>"
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "formato de token inválido (usar 'Bearer <token>')"})
			return
		}

		tokenString := parts[1]

		// 3. Parsear y validar el token
		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			// Validar el algoritmo de firma
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("método de firma inesperado: %v", token.Header["alg"])
			}
			// Retornar la clave secreta (la misma que usamos en Login)
			secret := os.Getenv("JWT_SECRET")
			if secret == "" {
				secret = "secreto_super_seguro_cambiar_en_produccion"
			}
			return []byte(secret), nil
		})

		// 4. Verificar errores o expiración
		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "token inválido o expirado"})
			return
		}

		// 5. Extraer datos (Claims) y pasarlos al contexto
		if claims, ok := token.Claims.(jwt.MapClaims); ok {
			// Guardamos el userID en el contexto de Gin para que el Handler lo use
			c.Set("userID", claims["sub"])
			c.Set("role", claims["role"])
		} else {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "error procesando claims"})
			return
		}

		// Continuar a la siguiente función (el Handler real)
		c.Next()
	}
}