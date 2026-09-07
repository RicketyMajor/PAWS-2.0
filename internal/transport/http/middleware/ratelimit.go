package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

// visitorTTL discards buckets that have gone quiet. Without it the map keeps an
// entry for every IP ever seen, and its size is decided by whoever calls us.
const visitorTTL = 10 * time.Minute

type visitor struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

// RateLimitByIP throttles each client IP to a token bucket that refills at r and
// holds burst tokens. Callers over the limit get 429 and the handler never runs.
//
// The returned handler owns its buckets, so two routes share a budget only when
// they share one instance of it.
//
// ponytail: buckets live in this process. The free plan runs a single instance, so
// that is the whole picture today; move them to Redis (already a dependency) if a
// second instance ever appears, since each would grant the full rate on its own.
func RateLimitByIP(r rate.Limit, burst int) gin.HandlerFunc {
	var mu sync.Mutex
	visitors := make(map[string]*visitor)
	lastSweep := time.Now()

	return func(c *gin.Context) {
		ip := c.ClientIP()

		mu.Lock()
		now := time.Now()
		// Sweeping on access keeps this to one goroutine and one lock. The map only
		// grows between sweeps, and a sweep is O(n) once every visitorTTL.
		if now.Sub(lastSweep) > visitorTTL {
			for key, v := range visitors {
				if now.Sub(v.lastSeen) > visitorTTL {
					delete(visitors, key)
				}
			}
			lastSweep = now
		}

		v, ok := visitors[ip]
		if !ok {
			v = &visitor{limiter: rate.NewLimiter(r, burst)}
			visitors[ip] = v
		}
		v.lastSeen = now
		allowed := v.limiter.Allow()
		mu.Unlock()

		if !allowed {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "Too many requests, please try again in a moment",
			})
			return
		}

		c.Next()
	}
}
