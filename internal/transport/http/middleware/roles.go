// Package middleware provides HTTP middleware functions.
package middleware

import (
	"net/http"
	"github.com/gin-gonic/gin"
)

// RequireRole is a Gin middleware that checks if the authenticated user has a specific role.
func RequireRole(requiredRole string) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 1. Get the role that the AuthMiddleware stored in the context.
		role := c.GetString("role")
		
		// 2. Verify if the user's role matches the required role.
		if role != requiredRole {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
				"error": "Access denied: Requires " + requiredRole + " privileges",
			})
			return
		}

		c.Next()
	}
}