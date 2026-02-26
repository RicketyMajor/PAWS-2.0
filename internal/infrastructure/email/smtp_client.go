package email

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
)

type EmailClient struct {
	apiKey string
	sender string
}

// NewEmailClient inicializa el despachador HTTP nativo
func NewEmailClient() *EmailClient {
	apiKey := os.Getenv("BREVO_API_KEY")
	sender := os.Getenv("BREVO_SENDER_EMAIL")

	if apiKey == "" {
		log.Println("AVISO: BREVO_API_KEY no configurada. Los correos funcionarán en modo simulación.")
	}

	return &EmailClient{
		apiKey: apiKey,
		sender: sender,
	}
}

// Send despacha el correo usando la API REST sobre el puerto seguro 443 (HTTPS)
func (c *EmailClient) Send(to, subject, body string) error {
	// Modo Simulación (Si faltan variables de entorno)
	if c.apiKey == "" || c.sender == "" {
		log.Printf("\n========== [MOCK EMAIL] ==========\nPara: %s\nAsunto: %s\nCuerpo:\n%s\n==================================\n", to, subject, body)
		return nil
	}

	url := "https://api.brevo.com/v3/smtp/email"

	// 1. Ensamblar el Payload JSON
	payload := map[string]interface{}{
		"sender": map[string]string{
			"name":  "PAWS Security",
			"email": c.sender,
		},
		"to": []map[string]string{
			{"email": to},
		},
		"subject":     subject,
		"textContent": body,
	}

	jsonData, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("error serializando json: %v", err)
	}

	// 2. Crear la petición HTTP
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("error creando request: %v", err)
	}

	// 3. Inyectar cabeceras de seguridad
	req.Header.Set("accept", "application/json")
	req.Header.Set("api-key", c.apiKey)
	req.Header.Set("content-type", "application/json")

	// 4. Disparar sobre puerto 443
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("timeout o error de red contactando API de correos: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("rechazo de la API (HTTP %d): %s", resp.StatusCode, string(bodyBytes))
	}

	log.Printf("[Worker email_notifications] Correo entregado exitosamente vía HTTP a: %s", to)
	return nil
}
