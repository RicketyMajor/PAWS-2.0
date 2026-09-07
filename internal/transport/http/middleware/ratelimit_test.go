package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

// hit sends one request from the given IP through a router guarded by limit.
func hit(t *testing.T, r *gin.Engine, ip string) int {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/auth/otp/request", nil)
	req.RemoteAddr = ip + ":54321"
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w.Code
}

func routerWith(limit gin.HandlerFunc) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/auth/otp/request", limit, func(c *gin.Context) { c.Status(http.StatusOK) })
	return r
}

// The burst is what a real person uses: a few tries in a row must all go through,
// and the one after the bucket empties must not.
func TestBurstIsAllowedThenRequestsAreRejected(t *testing.T) {
	r := routerWith(RateLimitByIP(rate.Every(time.Hour), 3))

	for i := 1; i <= 3; i++ {
		if code := hit(t, r, "203.0.113.7"); code != http.StatusOK {
			t.Fatalf("request %d within burst: got %d, want 200", i, code)
		}
	}

	if code := hit(t, r, "203.0.113.7"); code != http.StatusTooManyRequests {
		t.Fatalf("request past the burst: got %d, want 429", code)
	}
}

// Budgets are per IP. Without this, one noisy caller would lock out everyone else —
// a denial of service handed to the attacker by the defence itself.
func TestOneAddressExhaustingItsBudgetDoesNotBlockAnother(t *testing.T) {
	r := routerWith(RateLimitByIP(rate.Every(time.Hour), 1))

	if code := hit(t, r, "203.0.113.7"); code != http.StatusOK {
		t.Fatalf("first caller: got %d, want 200", code)
	}
	if code := hit(t, r, "203.0.113.7"); code != http.StatusTooManyRequests {
		t.Fatalf("first caller past its burst: got %d, want 429", code)
	}

	if code := hit(t, r, "198.51.100.9"); code != http.StatusOK {
		t.Fatalf("second caller: got %d, want 200", code)
	}
}

// Two routes sharing one instance share one budget. main.go relies on this to keep
// the three mail-sending routes on a single allowance instead of one each.
func TestRoutesSharingAnInstanceShareTheBudget(t *testing.T) {
	gin.SetMode(gin.TestMode)
	limit := RateLimitByIP(rate.Every(time.Hour), 1)
	r := gin.New()
	ok := func(c *gin.Context) { c.Status(http.StatusOK) }
	r.POST("/auth/otp/request", limit, ok)
	r.POST("/auth/forgot-password", limit, ok)

	if code := hit(t, r, "203.0.113.7"); code != http.StatusOK {
		t.Fatalf("first route: got %d, want 200", code)
	}

	req := httptest.NewRequest(http.MethodPost, "/auth/forgot-password", nil)
	req.RemoteAddr = "203.0.113.7:54321"
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("second route on the same budget: got %d, want 429", w.Code)
	}
}
