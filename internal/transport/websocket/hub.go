package websocket

import (
	"context"
	"log"
	"os"

	"github.com/redis/go-redis/v9"
)

// Hub mantiene el conjunto de clientes activos y transmite mensajes
type Hub struct {
	// Clientes registrados
	Clients map[*Client]bool

	// Mensajes entrantes (desde los clientes locales)
	Broadcast chan []byte

	// Solicitudes de registro y desregistro
	Register   chan *Client
	Unregister chan *Client

	// Cliente Redis para Pub/Sub
	RedisClient *redis.Client
}

func NewHub() *Hub {
	// Configurar conexión a Redis
	rdb := redis.NewClient(&redis.Options{
		Addr: os.Getenv("REDIS_HOST") + ":" + os.Getenv("REDIS_PORT"),
		// Password: "", // Usar si tienes pass
		DB: 0,
	})

	return &Hub{
		Broadcast:   make(chan []byte),
		Register:    make(chan *Client),
		Unregister:  make(chan *Client),
		Clients:     make(map[*Client]bool),
		RedisClient: rdb,
	}
}

func (h *Hub) Run() {
	// 1. Iniciar suscripción a Redis en una goroutine separada
	// Esto permite escuchar lo que dicen otros servidores
	go h.subscribeToRedis()

	for {
		select {
		case client := <-h.Register:
			h.Clients[client] = true
			log.Printf("[CONNECT] Cliente conectado: %s", client.UserID)

		case client := <-h.Unregister:
			if _, ok := h.Clients[client]; ok {
				delete(h.Clients, client)
				close(client.Send)
				log.Printf("[DISCONNECT] Cliente desconectado: %s", client.UserID)
			}

		case message := <-h.Broadcast:
			// 2. Cuando un usuario local envía un mensaje:
			// NO lo enviamos directamente a los clientes locales todavía.
			// Lo publicamos en Redis para que TODOS los servidores (incluido este) se enteren.
			err := h.RedisClient.Publish(context.Background(), "paws_chat", message).Err()
			if err != nil {
				log.Printf("Error publicando en Redis: %v", err)
			}
		}
	}
}

// subscribeToRedis escucha el canal global y reparte a los usuarios locales
func (h *Hub) subscribeToRedis() {
	ctx := context.Background()
	// Suscribirse al canal "paws_chat"
	pubsub := h.RedisClient.Subscribe(ctx, "paws_chat")
	defer pubsub.Close()

	ch := pubsub.Channel()

	// Loop infinito recibiendo mensajes de Redis
	for msg := range ch {
		// Cuando llega un mensaje de Redis (sea mío o de otro server),
		// se lo envío a todos mis clientes locales conectados.
		for client := range h.Clients {
			select {
			case client.Send <- []byte(msg.Payload):
			default:
				close(client.Send)
				delete(h.Clients, client)
			}
		}
	}
}