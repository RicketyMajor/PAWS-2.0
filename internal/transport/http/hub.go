package http

import (
	"encoding/json"
	"log"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

// InputMessage: Lo que envía el Frontend (Flutter)
type InputMessage struct {
	MatchID uint   `json:"match_id"`
	Content string `json:"content"`
}

// OutputMessage: Lo que enviamos de vuelta al Frontend
type OutputMessage struct {
	Type    string      `json:"type"` // "new_message", "error", etc.
	Payload interface{} `json:"payload"`
}

type Hub struct {
	// Mapa de Clientes: UserID -> Puntero al Cliente
	// Esto nos permite buscar rápidamente "¿Dónde está conectado Juan?"
	clients map[uint]*Client

	// Inyectamos el servicio para guardar en BD
	chatService *services.ChatService

	// Canales
	broadcast  chan *ClientMessageWrapper // Canal interno modificado
	register   chan *Client
	unregister chan *Client
}

// Wrapper para saber quién envió el mensaje crudo
type ClientMessageWrapper struct {
	Client  *Client
	Message []byte
}

func NewHub(chatService *services.ChatService) *Hub {
	return &Hub{
		broadcast:   make(chan *ClientMessageWrapper),
		register:    make(chan *Client),
		unregister:  make(chan *Client),
		clients:     make(map[uint]*Client),
		chatService: chatService,
	}
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			// Registramos al usuario por su ID
			h.clients[client.userID] = client
			log.Printf("Usuario %d conectado. Total online: %d", client.userID, len(h.clients))

		case client := <-h.unregister:
			if _, ok := h.clients[client.userID]; ok {
				delete(h.clients, client.userID)
				close(client.send)
				log.Printf("Usuario %d desconectado", client.userID)
			}

		case wrapper := <-h.broadcast:
			// AQUÍ PROCESAMOS EL MENSAJE ENTRANTE
			h.handleMessage(wrapper.Client, wrapper.Message)
		}
	}
}

func (h *Hub) handleMessage(sender *Client, msgBytes []byte) {
	// 1. Parsear el JSON que viene de Flutter
	var input InputMessage
	if err := json.Unmarshal(msgBytes, &input); err != nil {
		log.Printf("Error JSON: %v", err)
		return
	}

	// 2. Guardar en Base de Datos (Persistencia)
	savedMsg, receiverID, err := h.chatService.SaveMessage(input.MatchID, sender.userID, input.Content)
	if err != nil {
		// Opcional: Enviar error al remitente
		sender.sendJSON("error", map[string]string{"message": err.Error()})
		return
	}

	// 3. Preparar respuesta para el Frontend
	response := OutputMessage{
		Type:    "new_message",
		Payload: savedMsg, // Enviamos el objeto Message completo con ID y timestamp
	}

	// 4. Enrutamiento Inteligente (Routing)
	
	// A) Enviar al DESTINATARIO (si está conectado)
	if receiver, ok := h.clients[receiverID]; ok {
		receiver.sendJSON(response.Type, response.Payload)
	}

	// B) Enviar confirmación al REMITENTE (para que pinte el doble check o actualice ID)
	sender.sendJSON(response.Type, response.Payload)
}

// Helper para enviar JSON bonito
func (c *Client) sendJSON(typeMsg string, payload interface{}) {
	msg := OutputMessage{Type: typeMsg, Payload: payload}
	bytes, _ := json.Marshal(msg)
	c.send <- bytes
}