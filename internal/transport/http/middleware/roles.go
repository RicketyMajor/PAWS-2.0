package middleware

import (
	"net/http"
	"github.com/gin-gonic/gin"
)

// RequireRole verifica que el usuario tenga el rol necesario (ej: "admin")
func RequireRole(requiredRole string) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 1. Obtenemos el rol que AuthMiddleware guardó
		role := c.GetString("role")
		
		// 2. Verificamos (Si no es admin, fuera)
		if role != requiredRole {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "Acceso denegado: Se requiere nivel " + requiredRole,
			})
			return
		}

		c.Next()
	}
}