// Package middleware provides HTTP middleware functions.
package middleware

import (
	"net/http"
	"github.com/gin-gonic/gin"
)

// CORSMiddleware sets the necessary headers to allow Cross-Origin Resource Sharing.
// NOTE: A similar, more robust middleware named 'LocalCORSMiddleware' exists in 'cmd/api/main.go'.
// This version might be deprecated or used in a different context.
func CORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Allow any origin to make requests. For production, this should be restricted.
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		
		// Allow credentials such as cookies, authorization headers, etc.
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		
		// Set the allowed HTTP headers in requests.
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		
		// Set the allowed HTTP methods.
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		// Handle preflight OPTIONS requests.
		// The browser sends this before the actual request to check for CORS permissions.
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}