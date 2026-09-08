package middleware

import (
	"fmt"
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
	return rateLimitBy(func(c *gin.Context) string { return c.ClientIP() }, r, burst)
}

// RateLimitByUser throttles each authenticated caller instead of each address.
// Mount it after AuthMiddleware.
//
// An IP budget is the wrong key once a route requires a token: addresses are cheap
// to rotate, while another account costs an OTP mail that the /auth limits already
// meter. Keying on the account is what makes a slow scrape visible as one caller.
//
// ponytail: process-local buckets, same ceiling as RateLimitByIP.
func RateLimitByUser(r rate.Limit, burst int) gin.HandlerFunc {
	return rateLimitBy(func(c *gin.Context) string {
		// AuthMiddleware stores the "sub" claim, which arrives as a JSON number:
		// c.GetString would yield "" for every caller and collapse them into one
		// shared bucket, turning the limit into a global lock. %v formats whatever
		// type it is, and the prefix keeps it from colliding with the IP fallback.
		if id, ok := c.Get("userID"); ok {
			return fmt.Sprintf("user:%v", id)
		}
		return c.ClientIP()
	}, r, burst)
}

// rateLimitBy is the shared bucket machinery. keyFn decides what a "caller" is.
func rateLimitBy(keyFn func(*gin.Context) string, r rate.Limit, burst int) gin.HandlerFunc {
	var mu sync.Mutex
	visitors := make(map[string]*visitor)
	lastSweep := time.Now()

	return func(c *gin.Context) {
		key := keyFn(c)

		mu.Lock()
		now := time.Now()
		// Sweeping on access keeps this to one goroutine and one lock. The map only
		// grows between sweeps, and a sweep is O(n) once every visitorTTL.
		if now.Sub(lastSweep) > visitorTTL {
			for k, v := range visitors {
				if now.Sub(v.lastSeen) > visitorTTL {
					delete(visitors, k)
				}
			}
			lastSweep = now
		}

		v, ok := visitors[key]
		if !ok {
			v = &visitor{limiter: rate.NewLimiter(r, burst)}
			visitors[key] = v
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
