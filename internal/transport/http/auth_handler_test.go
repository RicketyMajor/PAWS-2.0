package http

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

// respond runs respondOTPError against a throwaway context and reports what the
// client would receive.
func respond(t *testing.T, err error) (int, string) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPost, "/auth/otp/request", nil)

	respondOTPError(c, "OTP system error", err)
	return w.Code, w.Body.String()
}

// Throttling is the caller going too fast, not a fault on our side. Answering 500
// would tell the client to retry and hide a working defence behind a bug report.
func TestThrottledRequestIsReportedAsTooManyRequests(t *testing.T) {
	code, _ := respond(t, services.ErrOTPThrottled)
	if code != http.StatusTooManyRequests {
		t.Fatalf("throttled: got %d, want 429", code)
	}
}

// A spent budget is the service being out of capacity, not the caller misbehaving.
// 429 would tell this caller to slow down when the limit is shared by everyone.
func TestExhaustedBudgetIsReportedAsUnavailable(t *testing.T) {
	code, _ := respond(t, services.ErrMailBudgetExhausted)
	if code != http.StatusServiceUnavailable {
		t.Fatalf("budget exhausted: got %d, want 503", code)
	}
}

// Anything else really is ours.
func TestOtherDeliveryFailuresStayServerErrors(t *testing.T) {
	code, _ := respond(t, errors.New("brevo rejected the message"))
	if code != http.StatusInternalServerError {
		t.Fatalf("delivery failure: got %d, want 500", code)
	}
}

// The provider's rejection names hosts and can quote our own request. It belongs in
// the server log, never in the response.
func TestTheCauseNeverReachesTheClient(t *testing.T) {
	_, body := respond(t, errors.New("rejected by 10.0.0.4: api-key invalid"))
	for _, leak := range []string{"10.0.0.4", "api-key"} {
		if strings.Contains(body, leak) {
			t.Fatalf("response leaked %q: %s", leak, body)
		}
	}
}
