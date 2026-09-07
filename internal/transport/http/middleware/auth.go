// Package middleware provides HTTP middleware functions.
package middleware

import (
	"fmt"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// wsAuthSubprotocol is the first value the client offers in Sec-WebSocket-Protocol,
// marking the second value as the bearer token. The server echoes it back on upgrade.
const wsAuthSubprotocol = "bearer"

// AuthMiddleware is a Gin middleware for JWT-based authentication.
// It extracts the token from the Authorization header or, for WebSocket
// handshakes, from the Sec-WebSocket-Protocol header,
// validates it, and sets the user's ID and role in the Gin context.
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString := ""

		// 1. Attempt to get the token from the "Authorization" header.
		authHeader := c.GetHeader("Authorization")
		if authHeader != "" {
			parts := strings.Split(authHeader, " ")
			if len(parts) == 2 && parts[0] == "Bearer" {
				tokenString = parts[1]
			}
		}

		// 2. Browsers cannot set an Authorization header on a WebSocket handshake, so
		// the token rides in Sec-WebSocket-Protocol as "bearer, <token>". It must not
		// travel in the query string: Gin's logger records the path with its query, which
		// would write a valid session token into the platform log on every connection.
		if tokenString == "" {
			if proto := c.GetHeader("Sec-WebSocket-Protocol"); proto != "" {
				parts := strings.SplitN(proto, ",", 2)
				if len(parts) == 2 && strings.TrimSpace(parts[0]) == wsAuthSubprotocol {
					tokenString = strings.TrimSpace(parts[1])
				}
			}
		}

		// If the token is still empty after both attempts, return an error.
		if tokenString == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Authorization token is required"})
			return
		}

		// 3. Parse and validate the token.
		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
			}
			return []byte(os.Getenv("JWT_SECRET")), nil
		})

		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
			return
		}

		// 4. Extract claims and set them in the context for downstream handlers.
		if claims, ok := token.Claims.(jwt.MapClaims); ok {
			c.Set("userID", claims["sub"])
			c.Set("role", claims["role"])
		} else {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Error processing token claims"})
			return
		}

		c.Next()
	}
}
