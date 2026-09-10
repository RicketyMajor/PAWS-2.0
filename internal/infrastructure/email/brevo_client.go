package email

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

// httpClient is shared so connections are reused. The timeout matters: OTP mail is
// sent inside the registration request when async mode is off, so a stalled call
// would hang the user's signup instead of failing.
var httpClient = &http.Client{Timeout: 10 * time.Second}

// brevoEndpoint is a var, not a const, so tests can point it at a local server.
var brevoEndpoint = "https://api.brevo.com/v3/smtp/email"

type EmailClient struct {
	apiKey string
	sender string
}

// NewEmailClient inicializa el despachador HTTP nativo
func NewEmailClient() *EmailClient {
	apiKey := os.Getenv("BREVO_API_KEY")
	sender := os.Getenv("BREVO_SENDER_EMAIL")

	if apiKey == "" || sender == "" {
		if os.Getenv("EMAIL_SIMULATION") == "true" {
			log.Println("AVISO: correo en MODO SIMULACION. Los codigos se imprimen, no se envian.")
		} else {
			log.Println("ERROR: BREVO_API_KEY/BREVO_SENDER_EMAIL sin configurar. El registro fallara: " +
				"define ambas, o EMAIL_SIMULATION=true para desarrollo local.")
		}
	}

	return &EmailClient{
		apiKey: apiKey,
		sender: sender,
	}
}

// Send despacha el correo usando la API REST sobre el puerto seguro 443 (HTTPS)
func (c *EmailClient) Send(to, subject, body string) error {
	// Simulation prints the code instead of sending it. The flag is checked first and
	// unconditionally: someone who sets it wants nothing to leave the machine, even if
	// real credentials happen to be loaded from .env.
	if os.Getenv("EMAIL_SIMULATION") == "true" {
		log.Printf("\n========== [MOCK EMAIL] ==========\nPara: %s\nAsunto: %s\nCuerpo:\n%s\n==================================\n", to, subject, body)
		return nil
	}

	// Without the flag, missing credentials are a hard failure. Simulating silently
	// would make production answer "code sent" while delivering nothing, and would
	// write the one-time code to the platform log in cleartext.
	if c.apiKey == "" || c.sender == "" {
		return fmt.Errorf("servicio de correo no configurado: falta BREVO_API_KEY o BREVO_SENDER_EMAIL")
	}

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
	req, err := http.NewRequest("POST", brevoEndpoint, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("error creando request: %v", err)
	}

	// 3. Inyectar cabeceras de seguridad
	req.Header.Set("accept", "application/json")
	req.Header.Set("api-key", c.apiKey)
	req.Header.Set("content-type", "application/json")

	// 4. Disparar sobre puerto 443
	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("timeout o error de red contactando API de correos: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("rechazo de la API (HTTP %d): %s", resp.StatusCode, string(bodyBytes))
	}

	// Drain the body so the connection returns to the idle pool instead of being
	// closed, which would cost a fresh TLS handshake on every send.
	_, _ = io.Copy(io.Discard, resp.Body)

	log.Println("[email] delivered")
	return nil
}
