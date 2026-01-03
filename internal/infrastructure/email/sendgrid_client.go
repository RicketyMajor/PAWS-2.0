
package email

import (
	"fmt"
	"log"
	"os"

	"github.com/sendgrid/sendgrid-go"
	"github.com/sendgrid/sendgrid-go/helpers/mail"
)

type EmailClient struct {
	apiKey string
}

func NewEmailClient() *EmailClient {
	// Leemos la API Key desde variables de entorno
	apiKey := os.Getenv("SENDGRID_API_KEY")
	if apiKey == "" {
		log.Println("SENDGRID_API_KEY no configurada. Los correos se imprimirán en consola.")
	}
	return &EmailClient{apiKey: apiKey}
}

func (c *EmailClient) Send(to, subject, body string) error {
	// Modo Simulación (Si no hay API Key)
	if c.apiKey == "" {
		log.Printf("[MOCK EMAIL] To: %s | Subject: %s | Body: %s", to, subject, body)
		return nil
	}

	// Modo Real (SendGrid)
	from := mail.NewEmail("PAWS Security", "alonso.vera@mail.udp.cl") // Cambia esto por tu remitente verificado en SendGrid
	toUser := mail.NewEmail("Usuario", to)
	message := mail.NewSingleEmail(from, subject, toUser, body, body) // PlainText y HTML content iguales por ahora
	
	client := sendgrid.NewSendClient(c.apiKey)
	response, err := client.Send(message)
	
	if err != nil {
		return err
	}

	if response.StatusCode >= 400 {
		return fmt.Errorf("error enviando email, status: %d, body: %s", response.StatusCode, response.Body)
	}

	log.Printf("Email enviado real a %s via SendGrid", to)
	return nil
}