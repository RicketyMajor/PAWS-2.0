package http

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
)

// Configuración de WebSocket (CORS permisivo para desarrollo)
var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

// IncomingMessage define la estructura JSON que envía la App Móvil
type IncomingMessage struct {
	MatchID uint   `json:"match_id"`
	Content string `json:"content"`
}

// WSHandler orquesta todo
type WSHandler struct {
	hub         *Hub
	chatService *services.ChatService
}

// NewWSHandler recibe el Hub y el Servicio de Chat
func NewWSHandler(hub *Hub, chatService *services.ChatService) *WSHandler {
	return &WSHandler{
		hub:         hub,
		chatService: chatService,
	}
}

// HandleConnections es el endpoint GET /ws
func (h *WSHandler) HandleConnections(c *gin.Context) {
	// 1. Identificar al usuario (gracias al Middleware)
	userIDVal, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "No autorizado"})
		return
	}
	userID := userIDVal.(uint)

	// 2. Upgrade HTTP -> WebSocket
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println("Error upgrade websocket:", err)
		return
	}

	// 3. Crear Cliente y registrarlo en el Hub
	client := &Client{
		hub:    h.hub,
		conn:   conn,
		send:   make(chan []byte, 256),
		userID: userID,
	}
	h.hub.register <- client

	// Limpieza al desconectar
	defer func() {
		h.hub.unregister <- client
		conn.Close()
	}()

	// BUCLE DE LECTURA (Aquí interceptamos los mensajes)
	for {
		var req IncomingMessage
		// Leer JSON del WebSocket
		err := conn.ReadJSON(&req)
		if err != nil {
			// Si el cliente se desconecta, salimos del bucle
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("error websocket: %v", err)
			}
			break
		}

		// --- PUNTO CLAVE: PERSISTENCIA ---
		// Intentamos guardar en BD usando el ChatService.
		// Esto valida "Evil PAWS" y guarda en Postgres.
		msgSaved, err := h.chatService.SaveMessage(req.MatchID, userID, req.Content)
		if err != nil {
			// Si falla (ej: mala palabra), enviamos error solo a este usuario
			errMsg := map[string]string{"error": "Mensaje rechazado: " + err.Error()}
			conn.WriteJSON(errMsg)
			continue
		}

		// --- PUNTO CLAVE: DIFUSIÓN ---
		// Si se guardó con éxito, lo enviamos al Hub para que lo vean los demás.
		// Enviamos solo el contenido por ahora.
		response := []byte(msgSaved.Content) 
		h.hub.broadcast <- response
	}
}