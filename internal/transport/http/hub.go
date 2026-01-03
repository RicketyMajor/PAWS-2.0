package http

import (
	"encoding/json"
	"log"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging" // <--- IMPORTAR
)

// InputMessage: Lo que envía el Frontend (Flutter)
type InputMessage struct {
	MatchID uint   `json:"match_id"`
	Content string `json:"content"`
}

// OutputMessage: Lo que enviamos de vuelta al Frontend
type OutputMessage struct {
	Type    string      `json:"type"` 
	Payload interface{} `json:"payload"`
}

type Hub struct {
	clients map[uint]*Client
	chatService *services.ChatService
	
	// --- NUEVO: Cliente RabbitMQ ---
	mqClient *messaging.RabbitMQClient 

	broadcast  chan *ClientMessageWrapper
	register   chan *Client
	unregister chan *Client
}

type ClientMessageWrapper struct {
	Client  *Client
	Message []byte
}

// --- ACTUALIZAR CONSTRUCTOR ---
func NewHub(chatService *services.ChatService, mq *messaging.RabbitMQClient) *Hub {
	return &Hub{
		broadcast:   make(chan *ClientMessageWrapper),
		register:    make(chan *Client),
		unregister:  make(chan *Client),
		clients:     make(map[uint]*Client),
		chatService: chatService,
		mqClient:    mq, // Inyección
	}
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.clients[client.userID] = client
			log.Printf("Usuario %d conectado. Total online: %d", client.userID, len(h.clients))

		case client := <-h.unregister:
			if _, ok := h.clients[client.userID]; ok {
				delete(h.clients, client.userID)
				close(client.send)
				log.Printf("Usuario %d desconectado", client.userID)
			}

		case wrapper := <-h.broadcast:
			h.handleMessage(wrapper.Client, wrapper.Message)
		}
	}
}

func (h *Hub) handleMessage(sender *Client, msgBytes []byte) {
	// 1. Parsear
	var input InputMessage
	if err := json.Unmarshal(msgBytes, &input); err != nil {
		log.Printf("Error JSON: %v", err)
		return
	}

	// 2. Guardar en BD
	savedMsg, receiverID, err := h.chatService.SaveMessage(input.MatchID, sender.userID, input.Content)
	if err != nil {
		sender.sendJSON("error", map[string]string{"message": err.Error()})
		return
	}

	// 3. Preparar respuesta
	response := OutputMessage{
		Type:    "new_message",
		Payload: savedMsg,
	}

	// 4. Enrutamiento Inteligente + Notificaciones
	
	// A) Enviar confirmación al REMITENTE (siempre)
	sender.sendJSON(response.Type, response.Payload)

	// B) Intentar enviar al DESTINATARIO
	if receiver, isOnline := h.clients[receiverID]; isOnline {
		// CASO 1: Está ONLINE (Conectado al Socket) -> Enviar en vivo
		receiver.sendJSON(response.Type, response.Payload)
	} else {
		// CASO 2: Está OFFLINE -> Enviar Notificación Push (RabbitMQ) 
		h.sendPushNotification(receiverID, sender.userID, input.Content)
	}
}

// --- NUEVA FUNCIÓN PRIVADA PARA NOTIFICAR ---
func (h *Hub) sendPushNotification(receiverID, senderID uint, content string) {
	if h.mqClient == nil {
		return 
	}

	// Obtenemos nombre del remitente (Opcional, podrías consultarlo al userService si quisieras ser más preciso,
	// pero por rendimiento podemos poner "Nuevo Mensaje" o hacer una query rápida).
	// Para MVP rápido:
	
	event := services.NotificationEvent{
		UserID: receiverID,
		Title:  "Nuevo Mensaje",
		Body:   content, // "Hola, ¿cómo estás?"
		Type:   "message",
	}

	body, _ := json.Marshal(event)
	
	// Publicar a la cola 'push_notifications' (la misma que usaste para Match)
	err := h.mqClient.Publish("push_notifications", body)
	if err != nil {
		log.Printf("Error encolando notificación chat: %v", err)
	} else {
		log.Printf("Notificación de chat encolada para usuario %d", receiverID)
	}
}

// Helper
func (c *Client) sendJSON(typeMsg string, payload interface{}) {
	msg := OutputMessage{Type: typeMsg, Payload: payload}
	bytes, _ := json.Marshal(msg)
	c.send <- bytes
}