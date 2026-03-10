// Package http contains the WebSocket hub and client logic for real-time communication.
package http

import (
	"encoding/json"
	"log"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
)

// =========================================================================
// Message Structures
// =========================================================================

// InputMessage represents a message received from a WebSocket client.
type InputMessage struct {
	MatchID uint   `json:"match_id"`
	Content string `json:"content"`
}

// OutputMessage represents a message sent to a WebSocket client.
type OutputMessage struct {
	Type    string      `json:"type"` 
	Payload interface{} `json:"payload"`
}

// ClientMessageWrapper is a container for a message and its sender.
type ClientMessageWrapper struct {
	Client  *Client
	Message []byte
}

// =========================================================================
// Hub Definition
// =========================================================================

// Hub maintains the set of active clients and broadcasts messages to them.
type Hub struct {
	clients     map[uint]*Client
	chatService *services.ChatService
	mqClient    *messaging.RabbitMQClient 

	broadcast  chan *ClientMessageWrapper
	register   chan *Client
	unregister chan *Client
}

// NewHub creates a new Hub instance.
func NewHub(chatService *services.ChatService, mq *messaging.RabbitMQClient) *Hub {
	return &Hub{
		broadcast:   make(chan *ClientMessageWrapper),
		register:    make(chan *Client),
		unregister:  make(chan *Client),
		clients:     make(map[uint]*Client),
		chatService: chatService,
		mqClient:    mq,
	}
}

// =========================================================================
// Hub Lifecycle
// =========================================================================

// Run starts the hub's event loop.
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.clients[client.userID] = client
			log.Printf("User %d connected. Total online: %d", client.userID, len(h.clients))

		case client := <-h.unregister:
			if _, ok := h.clients[client.userID]; ok {
				delete(h.clients, client.userID)
				close(client.send)
				log.Printf("User %d disconnected", client.userID)
			}

		case wrapper := <-h.broadcast:
			h.handleMessage(wrapper.Client, wrapper.Message)
		}
	}
}

// =========================================================================
// Message Handling
// =========================================================================

// handleMessage processes incoming messages from clients.
func (h *Hub) handleMessage(sender *Client, msgBytes []byte) {
	// 1. Parse the incoming message
	var input InputMessage
	if err := json.Unmarshal(msgBytes, &input); err != nil {
		log.Printf("JSON unmarshal error: %v", err)
		return
	}

	// 2. Save the message to the database
	savedMsg, receiverID, err := h.chatService.SaveMessage(input.MatchID, sender.userID, input.Content)
	if err != nil {
		sender.sendJSON("error", map[string]string{"message": err.Error()})
		return
	}

	// 3. Prepare the outbound message
	response := OutputMessage{
		Type:    "new_message",
		Payload: savedMsg,
	}

	// 4. Smart Routing & Push Notifications
	// A) Send confirmation to the sender (always)
	sender.sendJSON(response.Type, response.Payload)

	// B) Attempt to deliver to the recipient
	if receiver, isOnline := h.clients[receiverID]; isOnline {
		// Case 1: Recipient is ONLINE -> deliver via WebSocket
		receiver.sendJSON(response.Type, response.Payload)
	} else {
		// Case 2: Recipient is OFFLINE -> send a push notification via RabbitMQ
		h.sendPushNotification(receiverID, sender.userID, input.Content)
	}
}

// sendPushNotification publishes a push notification event to RabbitMQ.
func (h *Hub) sendPushNotification(receiverID, senderID uint, content string) {
	if h.mqClient == nil {
		return 
	}
	
	event := services.NotificationEvent{
		UserID: receiverID,
		Title:  "New Message",
		Body:   content,
		Type:   "message",
	}

	body, _ := json.Marshal(event)
	
	err := h.mqClient.Publish("push_notifications", body)
	if err != nil {
		log.Printf("Error queueing chat notification: %v", err)
	} else {
		log.Printf("Chat notification queued for user %d", receiverID)
	}
}

// =========================================================================
// Client Helper
// =========================================================================

// sendJSON is a helper to marshal a payload and send it to a client.
func (c *Client) sendJSON(typeMsg string, payload interface{}) {
	msg := OutputMessage{Type: typeMsg, Payload: payload}
	bytes, _ := json.Marshal(msg)
	c.send <- bytes
}