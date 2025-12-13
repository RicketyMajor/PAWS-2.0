package http

import (
	"fmt" // <--- IMPORTANTE: Asegúrate de agregar este import
	"log"
	"net/http"

	"github.com/RicketyMajor/PAWS-2.0/internal/transport/websocket" // <--- Ajusta TU_USUARIO
	"github.com/gin-gonic/gin"
	gws "github.com/gorilla/websocket"
)

var upgrader = gws.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

type WSHandler struct {
	hub *websocket.Hub
}

func NewWSHandler(hub *websocket.Hub) *WSHandler {
	return &WSHandler{hub: hub}
}

func (h *WSHandler) HandleConnections(c *gin.Context) {
	// 1. Obtener UserID del token
	userIDFloat, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	// 2. CORRECCIÓN: Usar la variable userIDFloat
	// El JWT devuelve números como float64. Lo convertimos a entero y luego a texto.
	id := int(userIDFloat.(float64)) 
	userID := fmt.Sprintf("user_%d", id) // Ej: "user_1"

	// 3. Actualizar a WebSocket
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println("Error upgrading to websocket:", err)
		return
	}

	// 4. Registrar cliente
	client := &websocket.Client{
		Hub:    h.hub,
		Conn:   conn,
		Send:   make(chan []byte, 256),
		UserID: userID,
	}
	client.Hub.Register <- client

	go client.WritePump()
	go client.ReadPump()
}