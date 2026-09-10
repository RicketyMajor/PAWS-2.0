package domain

import (
	"encoding/json"
	"strings"
	"testing"
)

// A User reaches a response through four eager loads, two of them on unauthenticated
// routes, so the default projection is the public one. These two tests are the guard:
// the first fails if `json:"-"` ever comes off Email or Run, the second fails if the
// owner's own profile stops carrying them.
func sampleUser() User {
	return User{
		Name:  "Ada",
		Email: "ada@example.com",
		Run:   "18.724.494-3",
		Phone: "+56911111111",
		Role:  "rescuer",
	}
}

func TestUserJSONWithholdsEmailAndRun(t *testing.T) {
	b, err := json.Marshal(sampleUser())
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	body := string(b)

	for _, leak := range []string{"ada@example.com", "18.724.494-3", `"email"`, `"run"`} {
		if strings.Contains(body, leak) {
			t.Errorf("the public projection of a User carries %q: %s", leak, body)
		}
	}

	// The public fields must survive, or the swipe deck and the public profile break.
	for _, keep := range []string{"Ada", "+56911111111", "rescuer"} {
		if !strings.Contains(body, keep) {
			t.Errorf("the public projection dropped %q: %s", keep, body)
		}
	}
}

func TestSelfUserJSONCarriesEmailAndRun(t *testing.T) {
	b, err := json.Marshal(NewSelfUser(sampleUser()))
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var got map[string]any
	if err := json.Unmarshal(b, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if got["email"] != "ada@example.com" {
		t.Errorf("SelfUser must carry the owner's email, got %v", got["email"])
	}
	if got["run"] != "18.724.494-3" {
		t.Errorf("SelfUser must carry the owner's run, got %v", got["run"])
	}
	if got["name"] != "Ada" {
		t.Errorf("SelfUser must keep the public fields, got %v", got["name"])
	}
}
