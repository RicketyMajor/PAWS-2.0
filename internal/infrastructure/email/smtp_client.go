package email

import (
	"fmt"
	"log"
	"net/smtp"
	"os"
)

type EmailClient struct {
	senderEmail string
	senderPass  string
	smtpHost    string
	smtpPort    string
}

// NewEmailClient inicializa el despachador SMTP nativo
func NewEmailClient() *EmailClient {
	email := os.Getenv("SMTP_EMAIL")
	password := os.Getenv("SMTP_PASSWORD")

	if email == "" || password == "" {
		log.Println("AVISO: SMTP_EMAIL o SMTP_PASSWORD no configuradas. Los correos funcionarán en modo simulación.")
	}

	return &EmailClient{
		senderEmail: email,
		senderPass:  password,
		smtpHost:    "smtp.gmail.com",
		smtpPort:    "587",
	}
}

// Send despacha el correo usando SMTP nativo
func (c *EmailClient) Send(to, subject, body string) error {
	// Modo Simulación (Si faltan variables de entorno)
	if c.senderEmail == "" || c.senderPass == "" {
		log.Printf("\n========== [MOCK EMAIL] ==========\nPara: %s\nAsunto: %s\nCuerpo:\n%s\n==================================\n", to, subject, body)
		return nil
	}

	// Configurar la autenticación
	auth := smtp.PlainAuth("", c.senderEmail, c.senderPass, c.smtpHost)

	// Construir el mensaje con cabeceras correctas
	message := fmt.Sprintf("From: PAWS Security <%s>\r\n"+
		"To: %s\r\n"+
		"Subject: %s\r\n"+
		"Content-Type: text/plain; charset=UTF-8\r\n\r\n"+
		"%s\r\n", c.senderEmail, to, subject, body)

	address := fmt.Sprintf("%s:%s", c.smtpHost, c.smtpPort)

	// Enviar el correo
	err := smtp.SendMail(address, auth, c.senderEmail, []string{to}, []byte(message))
	if err != nil {
		return fmt.Errorf("error enviando correo por SMTP: %v", err)
	}

	log.Printf("[Worker email_notifications] Correo entregado exitosamente vía SMTP a: %s", to)
	return nil
}
