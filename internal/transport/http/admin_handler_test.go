package http

import (
	"encoding/json"
	"testing"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
)

// domain.User withholds email and run, so the admin dashboard — which identifies two
// accounts by email, since names are not unique — only works while the report response
// re-adds them. Nothing else exercises this path, and losing it fails silently.
func TestAdminReportCarriesBothIdentifiers(t *testing.T) {
	report := domain.Report{
		Reporter: domain.User{Name: "Ada", Email: "ada@example.com", Run: "18.724.494-3"},
		Reported: domain.User{Name: "Bob", Email: "bob@example.com", Run: "16.246.714-K"},
	}

	b, err := json.Marshal(newAdminReport(report))
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var got struct {
		Reporter struct{ Email, Run string }
		Reported struct{ Email, Run string }
	}
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if got.Reporter.Email != "ada@example.com" || got.Reporter.Run != "18.724.494-3" {
		t.Errorf("the reporter reached the admin without identifiers: %+v", got.Reporter)
	}
	if got.Reported.Email != "bob@example.com" || got.Reported.Run != "16.246.714-K" {
		t.Errorf("the reported user reached the admin without identifiers: %+v", got.Reported)
	}
}
