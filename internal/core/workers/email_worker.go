package workers

import (
	"encoding/json"

	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/email"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
)

type EmailEvent struct {
	To      string `json:"to"`
	Subject string `json:"subject"`
	Body    string `json:"body"`
}

// StartEmailConsumer inicia el proceso con auto-recovery
func StartEmailConsumer(rabbitURL string, emailClient *email.EmailClient) {
	messaging.ConsumeWithRetry(rabbitURL, "email_notifications", func(body []byte) error {
		var event EmailEvent
		if err := json.Unmarshal(body, &event); err != nil {
			return err
		}
		// Intentar enviar el correo
		return emailClient.Send(event.To, event.Subject, event.Body)
	})
}
