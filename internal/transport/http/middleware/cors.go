package middleware

import (
	"net/http"
	"github.com/gin-gonic/gin"
)

// CORSMiddleware permite que navegadores (Flutter Web) consuman la API
func CORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Permitir cualquier origen (puedes restringirlo a tu dominio de Vercel en prod)
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		
		// Permitir credenciales (cookies, auth headers)
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		
		// Headers permitidos (necesitamos Authorization para el JWT)
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		
		// Métodos permitidos
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		// Manejo de la solicitud OPTIONS (Preflight)
		// El navegador pregunta "¿Puedo hablar contigo?" antes de enviar datos reales
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}