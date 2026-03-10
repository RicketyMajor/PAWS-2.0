// Package messaging provides functionality for interacting with RabbitMQ.
package messaging

import (
	"context"
	"fmt"
	"log"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

// =========================================================================
// Client Definition
// =========================================================================

// RabbitMQClient holds the connection and channel for interacting with RabbitMQ.
type RabbitMQClient struct {
	conn *amqp.Connection
	ch   *amqp.Channel
}

// =========================================================================
// Connection Handling
// =========================================================================

// ConnectRabbitMQ establishes a connection to RabbitMQ for publishing messages.
// It includes a retry mechanism for initial connection failures.
func ConnectRabbitMQ(url string) (*RabbitMQClient, error) {
	var conn *amqp.Connection
	var err error

	// Retry connection for robustness
	for i := 0; i < 5; i++ {
		conn, err = amqp.Dial(url)
		if err == nil {
			break
		}
		log.Printf("RabbitMQ not ready, retrying in 2s... (%d/5)", i+1)
		time.Sleep(2 * time.Second)
	}
	if err != nil {
		return nil, fmt.Errorf("could not connect to RabbitMQ: %v", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		return nil, fmt.Errorf("could not open a channel: %v", err)
	}

	// Declare critical queues to ensure they exist on the server.
	queues := []string{"email_notifications", "push_notifications"}
	for _, q := range queues {
		_, err = ch.QueueDeclare(q, true, false, false, false, nil)
		if err != nil {
			return nil, err
		}
	}

	return &RabbitMQClient{conn: conn, ch: ch}, nil
}

// =========================================================================
// Client Methods
// =========================================================================

// Publish sends a message to the specified queue.
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
			DeliveryMode: amqp.Persistent, // Ensure messages survive broker restarts.
		},
	)
}

// GetChannel returns the underlying AMQP channel.
func (c *RabbitMQClient) GetChannel() *amqp.Channel {
	return c.ch
}

// =========================================================================
// Resilient Consumer
// =========================================================================

// ConsumeWithRetry provides a resilient consumer that automatically reconnects
// in case of network failures. It runs in an infinite loop.
func ConsumeWithRetry(url, queueName string, handler func([]byte) error) {
	for {
		conn, err := amqp.Dial(url)
		if err != nil {
			log.Printf("[Worker %s] Network error: %v. Retrying in 5s...", queueName, err)
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

		log.Printf("[Worker %s] Connected and consuming messages via CloudAMQP", queueName)

		// This loop blocks, reading messages. If the connection drops,
		// the 'msgs' channel will close, breaking the loop and triggering a reconnect.
		for d := range msgs {
			err := handler(d.Body)
			if err != nil {
				log.Printf("[Worker %s] Error processing message: %v", queueName, err)
				d.Nack(false, false) // Discard corrupted message to prevent queue blockage.
			} else {
				d.Ack(false) // Acknowledge successful processing.
			}
		}

		log.Printf("[Worker %s] Connection lost. Reconnecting in the background...", queueName)
		conn.Close()
		time.Sleep(5 * time.Second)
	}
}
