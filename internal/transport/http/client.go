package http

import (
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 512
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// IMPORTANTE: Permitir CORS para que Flutter (emulador) pueda conectarse
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

// Client es un intermediario entre el websocket y el Hub.
type Client struct {
	hub *Hub
	// La conexión websocket real
	conn *websocket.Conn
	// Canal con buffer para mensajes salientes
	send chan []byte
	// ID del usuario autenticado (para saber quién es quién)
	userID uint
}

// readPump bombea mensajes del websocket al Hub.
func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()
	c.conn.SetReadLimit(maxMessageSize)
	// ... (configuración de tiempos igual que antes) ...
	
	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("error: %v", err)
			}
			break
		}
		
		// CAMBIO AQUÍ: Enviamos el wrapper con "c" (el cliente) y el mensaje
		c.hub.broadcast <- &ClientMessageWrapper{
			Client:  c,
			Message: message,
		}
	}
}

// writePump bombea mensajes del Hub al websocket.
// (El Hub dice "envía esto" -> writePump lo agarra -> lo escribe en el socket del usuario)
func (c *Client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()
	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// El Hub cerró el canal
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			// Agregar mensajes en cola al mismo paquete WebSocket si los hay
			n := len(c.send)
			for i := 0; i < n; i++ {
				w.Write(<-c.send)
			}

			if err := w.Close(); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// ServeWs maneja las solicitudes websocket del endpoint GET /ws
func ServeWs(hub *Hub, c *gin.Context, userID uint) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println(err)
		return
	}
	client := &Client{hub: hub, conn: conn, send: make(chan []byte, 256), userID: userID}
	client.hub.register <- client

	// Ejecutar las bombas de lectura y escritura en goroutines separadas
	go client.writePump()
	go client.readPump()
}