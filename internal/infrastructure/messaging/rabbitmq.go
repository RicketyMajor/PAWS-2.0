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

// ConnectRabbitMQ establece la conexión y declara la Queue inicial
func ConnectRabbitMQ(url string) (*RabbitMQClient, error) {
	var conn *amqp.Connection
	var err error

	// Lógica de reintento simple (Wait for infrastructure)
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

	// Declarar la cola "email_notifications"
	// Durable: true (sobrevive reinicios), AutoDelete: false
	_, err = ch.QueueDeclare(
		"email_notifications", // nombre
		true,                  // durable
		false,                 // delete when unused
		false,                 // exclusive
		false,                 // no-wait
		nil,                   // arguments
	)
	if err != nil {
		return nil, err
	}

	return &RabbitMQClient{conn: conn, ch: ch}, nil
}

// Publish envía un mensaje a la cola
func (c *RabbitMQClient) Publish(queueName string, body []byte) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	return c.ch.PublishWithContext(ctx,
		"",        // exchange (default)
		queueName, // routing key (queue name)
		false,     // mandatory
		false,     // immediate
		amqp.Publishing{
			ContentType: "application/json",
			Body:        body,
			DeliveryMode: amqp.Persistent, // Guardar en disco por seguridad
		})
}

// Close cierra recursos
func (c *RabbitMQClient) Close() {
	c.ch.Close()
	c.conn.Close()
}

// GetChannel exporta el canal para consumidores
func (c *RabbitMQClient) GetChannel() *amqp.Channel {
	return c.ch
}