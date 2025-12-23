package workers

import (
	"encoding/json"
	"log"

	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/email"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
)

type EmailEvent struct {
	To      string `json:"to"`
	Subject string `json:"subject"`
	Body    string `json:"body"`
}

// StartEmailConsumer inicia el proceso en segundo plano
func StartEmailConsumer(mq *messaging.RabbitMQClient, emailClient *email.EmailClient) {
	ch := mq.GetChannel()

	// Consumir de la cola declarada anteriormente
	msgs, err := ch.Consume(
		"email_notifications", // queue
		"",                    // consumer name
		false,                 // auto-ack (Falso: confirmaremos manualmente tras enviar)
		false,                 // exclusive
		false,                 // no-local
		false,                 // no-wait
		nil,                   // args
	)
	if err != nil {
		log.Printf("Error registrando consumidor RabbitMQ: %v", err)
		return
	}

	log.Println("Worker de Emails iniciado. Esperando mensajes...")

	// Bucle infinito leyendo el canal
	go func() {
		for d := range msgs {
			var event EmailEvent
			err := json.Unmarshal(d.Body, &event)
			if err != nil {
				log.Printf("Error decodificando evento: %v", err)
				d.Ack(false) // Confirmamos para sacarlo de la cola aunque esté malo (Dead Letter en prod)
				continue
			}

			// Intentar enviar el correo
			err = emailClient.Send(event.To, event.Subject, event.Body)
			if err != nil {
				log.Printf("Error enviando email: %v", err)
				// d.Nack(false, true) // Reencolar si falla (Cuidado con loops infinitos)
			} else {
				// Confirmar éxito a RabbitMQ
				d.Ack(false)
			}
		}
	}()
}