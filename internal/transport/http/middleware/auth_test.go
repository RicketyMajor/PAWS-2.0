package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

const testSecret = "test-secret-for-middleware"

func signedToken(t *testing.T) string {
	t.Helper()
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":  float64(42),
		"role": "adopter",
	})
	s, err := tok.SignedString([]byte(testSecret))
	if err != nil {
		t.Fatalf("signing test token: %v", err)
	}
	return s
}

// run sends one request through the middleware and reports the status plus the
// userID the middleware published, if it got that far.
func run(t *testing.T, decorate func(*http.Request)) (int, interface{}) {
	t.Helper()
	t.Setenv("JWT_SECRET", testSecret)
	gin.SetMode(gin.TestMode)

	var seenUserID interface{}
	r := gin.New()
	r.GET("/ws", AuthMiddleware(), func(c *gin.Context) {
		seenUserID, _ = c.Get("userID")
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/ws", nil)
	decorate(req)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w.Code, seenUserID
}

func TestAuthorizationHeaderIsAccepted(t *testing.T) {
	code, userID := run(t, func(r *http.Request) {
		r.Header.Set("Authorization", "Bearer "+signedToken(t))
	})
	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200", code)
	}
	if userID != float64(42) {
		t.Errorf("userID = %v, want 42", userID)
	}
}

// Browsers cannot set an Authorization header on a WebSocket handshake, so the
// token arrives as the second value of Sec-WebSocket-Protocol.
func TestWebSocketSubprotocolIsAccepted(t *testing.T) {
	code, userID := run(t, func(r *http.Request) {
		r.Header.Set("Sec-WebSocket-Protocol", "bearer, "+signedToken(t))
	})
	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200", code)
	}
	if userID != float64(42) {
		t.Errorf("userID = %v, want 42", userID)
	}
}

// The query string must no longer authenticate anything. Gin logs the path with
// its query, so a token accepted here ends up in the platform log.
func TestQueryStringTokenIsRejected(t *testing.T) {
	tok := signedToken(t)
	t.Setenv("JWT_SECRET", testSecret)
	gin.SetMode(gin.TestMode)

	r := gin.New()
	r.GET("/ws", AuthMiddleware(), func(c *gin.Context) { c.Status(http.StatusOK) })

	req := httptest.NewRequest(http.MethodGet, "/ws?token="+tok, nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401: a token in the query string must not authenticate", w.Code)
	}
}

func TestMalformedSubprotocolIsRejected(t *testing.T) {
	cases := map[string]string{
		"missing marker": signedToken(t),
		"wrong marker":   "basic, " + signedToken(t),
		"marker only":    "bearer",
		"empty":          "",
	}
	for name, header := range cases {
		t.Run(name, func(t *testing.T) {
			code, _ := run(t, func(r *http.Request) {
				r.Header.Set("Sec-WebSocket-Protocol", header)
			})
			if code != http.StatusUnauthorized {
				t.Errorf("status = %d, want 401", code)
			}
		})
	}
}

func TestMissingTokenIsRejected(t *testing.T) {
	code, _ := run(t, func(r *http.Request) {})
	if code != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401", code)
	}
}
