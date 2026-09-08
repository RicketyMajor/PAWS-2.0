package main

import (
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

// The rule this guards: no personal data in logs. The query string is where a RUN and
// a pair of GPS coordinates travel, so the formatter must never print one.
func TestAccessLineDropsTheQueryString(t *testing.T) {
	cases := []struct {
		name string
		path string
		leak string
	}{
		{"a national id", "/api/v1/blacklist/search?rut=12345678-5", "12345678-5"},
		{"coordinates", "/api/v1/pets/nearby?lat=-33.4489&lng=-70.6693", "-33.4489"},
		{"an authenticated location trail", "/api/v1/matches/candidates?lat=-33.4&lon=-70.6", "-70.6"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			line := logWithoutQuery(gin.LogFormatterParams{
				TimeStamp:  time.Now(),
				StatusCode: 200,
				Latency:    time.Millisecond,
				ClientIP:   "203.0.113.7",
				Method:     "GET",
				Path:       tc.path,
			})

			if strings.Contains(line, tc.leak) {
				t.Fatalf("access line leaked %q:\n%s", tc.leak, line)
			}
			if strings.Contains(line, "?") {
				t.Fatalf("access line kept a query string:\n%s", line)
			}
			// The point is to redact, not to stop logging: the route must stay visible.
			if !strings.Contains(line, strings.SplitN(tc.path, "?", 2)[0]) {
				t.Fatalf("access line lost the path:\n%s", line)
			}
		})
	}
}

// A path with no query must survive untouched, or every other route loses its log.
func TestAccessLineKeepsAPlainPath(t *testing.T) {
	line := logWithoutQuery(gin.LogFormatterParams{
		TimeStamp: time.Now(), StatusCode: 200, Latency: time.Millisecond,
		ClientIP: "203.0.113.7", Method: "GET", Path: "/api/v1/health",
	})
	if !strings.Contains(line, "/api/v1/health") || !strings.Contains(line, "200") {
		t.Fatalf("plain path lost detail:\n%s", line)
	}
}
