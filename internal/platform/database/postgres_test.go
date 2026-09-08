package database

import (
	"bytes"
	"strings"
	"testing"

	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

// probe stands in for the tables whose bind parameters were seen in the Render
// log on 2026-09-07: the blacklist lookup, every login, and the nearby search.
// The columns matter, the model does not.
type probe struct {
	ID    uint
	Run   string
	Email string
	Lat   float64
}

// The values are synthetic but each stands for a real leak class: a national id,
// an address, and a GPS fix precise enough to be a location trail.
const (
	leakedRun   = "12345678-5"
	leakedEmail = "tester@example.com"
	leakedCoord = "33.4489"
)

// TestQueryLogKeepsTheSQLButNotTheValues pins both halves of the rule across
// every execution path the app uses. Dropping the values is half the job; a
// logger that also dropped the statement, its timing or its row count would pass
// a leak test and destroy the reason the log is set to Info in the first place.
//
// The two paths are not interchangeable: Scan swaps the configured logger for
// logger.Recorder before executing (gorm/finisher_api.go:527) and hands the real
// logger an already-interpolated string, so a fix that only covers Find leaves
// GetNearby — the coordinate query this rule exists for — still leaking.
func TestQueryLogKeepsTheSQLButNotTheValues(t *testing.T) {
	cases := []struct {
		name string
		run  func(*gorm.DB)
	}{
		{
			name: "Find",
			run: func(db *gorm.DB) {
				db.Where("run = ? AND email = ? AND cos(radians(?)) > lat",
					leakedRun, leakedEmail, -33.4489).Find(&[]probe{})
			},
		},
		{
			name: "Scan, the path GetNearby takes",
			run: func(db *gorm.DB) {
				db.Raw("SELECT * FROM probes WHERE run = ? AND email = ? AND cos(radians(?)) > lat",
					leakedRun, leakedEmail, -33.4489).Scan(&[]probe{})
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var out bytes.Buffer
			db, err := gorm.Open(sqlite.Open("file::memory:"), &gorm.Config{Logger: queryLogger(&out)})
			if err != nil {
				t.Fatalf("opening the probe database: %v", err)
			}
			if err := db.AutoMigrate(&probe{}); err != nil {
				t.Fatalf("migrating the probe table: %v", err)
			}

			out.Reset()
			tc.run(db)
			line := out.String()

			for _, leak := range []string{leakedRun, leakedEmail, leakedCoord} {
				if strings.Contains(line, leak) {
					t.Fatalf("query log leaked %q:\n%s", leak, line)
				}
			}
			// The point is to redact the values, not to stop logging queries.
			if !strings.Contains(line, "SELECT") || !strings.Contains(line, "probes") {
				t.Fatalf("query log lost the statement:\n%s", line)
			}
			if !strings.Contains(line, "[rows:") {
				t.Fatalf("query log lost the row count:\n%s", line)
			}
		})
	}
}
