package messaging

import (
	"context"
	"fmt"
	"log"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

type RabbitMQClient struct {
	conn *amqp.Connection
	ch   *amqp.Channel
}

// ConnectRabbitMQ establece la conexión estática para el PUBLICADOR (La API de Gin)
func ConnectRabbitMQ(url string) (*RabbitMQClient, error) {
	var conn *amqp.Connection
	var err error

	for i := 0; i < 5; i++ {
		conn, err = amqp.Dial(url)
		if err == nil {
			break
		}
		log.Printf("RabbitMQ no listo, reintentando en 2s... (%d/5)", i+1)
		time.Sleep(2 * time.Second)
	}

	if err != nil {
		return nil, fmt.Errorf("no se pudo conectar a RabbitMQ: %v", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		return nil, fmt.Errorf("no se pudo abrir canal: %v", err)
	}

	// Declarar colas críticas para asegurar que existan en la nube
	queues := []string{"email_notifications", "push_notifications"}
	for _, q := range queues {
		_, err = ch.QueueDeclare(q, true, false, false, false, nil)
		if err != nil {
			return nil, err
		}
	}

	return &RabbitMQClient{conn: conn, ch: ch}, nil
}

// Publish envía un mensaje a la cola
func (c *RabbitMQClient) Publish(queueName string, body []byte) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	return c.ch.PublishWithContext(ctx,
		"",        // exchange
		queueName, // routing key
		false,     // mandatory
		false,     // immediate
		amqp.Publishing{
			ContentType:  "application/json",
			Body:         body,
			DeliveryMode: amqp.Persistent, // Sobrevive reinicios de CloudAMQP
		},
	)
}

func (c *RabbitMQClient) GetChannel() *amqp.Channel {
	return c.ch
}

// --- NUEVO: Motor de Auto-Recovery para Workers ---
// Aísla la conexión del consumidor y la reconstruye silenciosamente si hay cortes de red
func ConsumeWithRetry(url, queueName string, handler func([]byte) error) {
	for {
		conn, err := amqp.Dial(url)
		if err != nil {
			log.Printf("[Worker %s] Error de red: %v. Reintentando en 5s...", queueName, err)
			time.Sleep(5 * time.Second)
			continue
		}

		ch, err := conn.Channel()
		if err != nil {
			conn.Close()
			time.Sleep(5 * time.Second)
			continue
		}

		msgs, err := ch.Consume(queueName, "", false, false, false, false, nil)
		if err != nil {
			conn.Close()
			time.Sleep(5 * time.Second)
			continue
		}

		log.Printf("[Worker %s] Conectado y en línea vía CloudAMQP", queueName)

		// El bucle bloquea el hilo leyendo mensajes. Si la conexión cae, el canal 'msgs' se cierra y rompe el bucle.
		for d := range msgs {
			err := handler(d.Body)
			if err != nil {
				log.Printf("[Worker %s] Error procesando mensaje: %v", queueName, err)
				_ = d.Ack(false) // Descartar mensaje corrupto para no atascar la cola
			} else {
				_ = d.Ack(false) // Confirmar éxito
			}
		}

		log.Printf("[Worker %s] Conexión nubososa perdida. Reconectando en segundo plano...", queueName)
		conn.Close()
		time.Sleep(5 * time.Second)
	}
}
