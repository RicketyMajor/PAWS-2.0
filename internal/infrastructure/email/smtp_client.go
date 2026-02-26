package email

import (
	"fmt"
	"log"
	"net/smtp"
	"os"
)

type EmailClient struct {
	host string
	port string
	user string
	pass string
}

// NewEmailClient inicializa el despachador nativo SMTP
func NewEmailClient() *EmailClient {
	host := os.Getenv("SMTP_HOST")
	if host == "" {
		log.Println("AVISO: SMTP_HOST no configurado. Los correos funcionarán en modo simulación (consola).")
	}

	return &EmailClient{
		host: host,
		port: os.Getenv("SMTP_PORT"),
		user: os.Getenv("SMTP_USER"),
		pass: os.Getenv("SMTP_PASS"),
	}
}

// Send despacha el correo usando el protocolo TCP/SMTP estándar
func (c *EmailClient) Send(to, subject, body string) error {
	// Modo Simulación (Si faltan variables de entorno)
	if c.host == "" || c.pass == "" {
		log.Printf("\n========== [MOCK EMAIL] ==========\nPara: %s\nAsunto: %s\nCuerpo:\n%s\n==================================\n", to, subject, body)
		return nil
	}

	// 1. Ensamblar los cabezales del correo (Headers)
	header := fmt.Sprintf("From: PAWS Security <%s>\r\n", c.user)
	header += fmt.Sprintf("To: %s\r\n", to)
	header += fmt.Sprintf("Subject: %s\r\n", subject)
	header += "MIME-version: 1.0;\r\n"
	header += "Content-Type: text/plain; charset=\"UTF-8\";\r\n\r\n"

	msg := []byte(header + body + "\r\n")

	// 2. Autenticación plana contra el servidor
	auth := smtp.PlainAuth("", c.user, c.pass, c.host)
	addr := fmt.Sprintf("%s:%s", c.host, c.port)

	// 3. Abrir socket TCP y enviar
	err := smtp.SendMail(addr, auth, c.user, []string{to}, msg)
	if err != nil {
		return fmt.Errorf("error del servidor SMTP: %v", err)
	}

	log.Printf("[Worker email_notifications] Correo de verificación entregado a: %s", to)
	return nil
}
