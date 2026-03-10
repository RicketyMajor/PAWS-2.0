// Package workers contains background consumers for message queues.
package workers

import (
	"encoding/json"

	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/email"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
)

// EmailEvent defines the structure of a message consumed from the email queue.
type EmailEvent struct {
	To      string `json:"to"`
	Subject string `json:"subject"`
	Body    string `json:"body"`
}

// StartEmailConsumer starts a resilient worker that consumes messages from the
// "email_notifications" queue and sends emails.
func StartEmailConsumer(rabbitURL string, emailClient *email.EmailClient) {
	// Use the resilient consumer to handle connection drops automatically.
	messaging.ConsumeWithRetry(rabbitURL, "email_notifications", func(body []byte) error {
		var event EmailEvent
		if err := json.Unmarshal(body, &event); err != nil {
			return err
		}
		// Attempt to send the email.
		return emailClient.Send(event.To, event.Subject, event.Body)
	})
}
