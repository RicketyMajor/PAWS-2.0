package email

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// withStubBrevo points the client at a local server for the duration of a test.
func withStubBrevo(t *testing.T, h http.HandlerFunc) {
	t.Helper()
	srv := httptest.NewServer(h)
	original := brevoEndpoint
	brevoEndpoint = srv.URL
	t.Cleanup(func() {
		brevoEndpoint = original
		srv.Close()
	})
}

// A rejection from Brevo must surface as an error. This is the regression that broke
// registration: a failed send reported success, so users waited for mail never sent.
func TestSendReturnsErrorWhenAPIRejects(t *testing.T) {
	withStubBrevo(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"message":"Key not found"}`))
	})

	c := &EmailClient{apiKey: "test-key", sender: "paws@example.com"}
	if err := c.Send("someone@example.com", "Subject", "body"); err == nil {
		t.Fatal("expected an error when the API returns 401, got nil")
	}
}

// Brevo names the address it rejected in its own message, and the caller logs the
// error this returns. Carrying that message through would put the address back in the
// service log by a second door, on a path reachable without authenticating.
func TestRejectionErrorCarriesNoRecipient(t *testing.T) {
	withStubBrevo(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"code":"invalid_parameter","message":"Invalid email: someone@example.com"}`))
	})

	c := &EmailClient{apiKey: "test-key", sender: "paws@example.com"}
	err := c.Send("someone@example.com", "Subject", "body")
	if err == nil {
		t.Fatal("expected an error when the API rejects the send, got nil")
	}
	if strings.Contains(err.Error(), "someone@example.com") {
		t.Errorf("the error names the recipient, which the caller writes to the log: %v", err)
	}
	if !strings.Contains(err.Error(), "invalid_parameter") {
		t.Errorf("the error dropped the code too, leaving nothing to diagnose with: %v", err)
	}
}

// The happy path must return nil and send a well-formed, authenticated request.
func TestSendDeliversAuthenticatedPayload(t *testing.T) {
	var gotKey string
	var gotBody map[string]interface{}

	withStubBrevo(t, func(w http.ResponseWriter, r *http.Request) {
		gotKey = r.Header.Get("api-key")
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, &gotBody)
		w.WriteHeader(http.StatusCreated)
	})

	c := &EmailClient{apiKey: "test-key", sender: "paws@example.com"}
	if err := c.Send("someone@example.com", "Your code", "12345"); err != nil {
		t.Fatalf("expected success, got %v", err)
	}

	if gotKey != "test-key" {
		t.Errorf("api-key header = %q, want %q", gotKey, "test-key")
	}
	if gotBody["subject"] != "Your code" {
		t.Errorf("subject = %v, want %q", gotBody["subject"], "Your code")
	}
	if gotBody["textContent"] != "12345" {
		t.Errorf("textContent = %v, want %q", gotBody["textContent"], "12345")
	}
}

// Simulation must be opted into. Without the flag an unconfigured client has to fail,
// or a deploy missing BREVO_API_KEY would report "code sent" and deliver nothing.
func TestSendFailsWhenUnconfiguredAndNotSimulating(t *testing.T) {
	withStubBrevo(t, func(w http.ResponseWriter, r *http.Request) {
		t.Error("unconfigured client must not make a network call")
	})
	t.Setenv("EMAIL_SIMULATION", "")

	c := &EmailClient{}
	if err := c.Send("someone@example.com", "Subject", "body"); err == nil {
		t.Fatal("expected an error when credentials are missing, got nil")
	}
}

// With the flag set, local development keeps working without a Brevo account.
func TestSendSimulatesWhenExplicitlyEnabled(t *testing.T) {
	withStubBrevo(t, func(w http.ResponseWriter, r *http.Request) {
		t.Error("simulation mode must not make a network call")
	})
	t.Setenv("EMAIL_SIMULATION", "true")

	c := &EmailClient{}
	if err := c.Send("someone@example.com", "Subject", "body"); err != nil {
		t.Fatalf("simulation mode should not error, got %v", err)
	}
}
