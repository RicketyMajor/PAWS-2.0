package websocket

import (
	"log"
	"time"
	"bytes"

	"github.com/gorilla/websocket"
)

var badWords = [][]byte{
	[]byte("tonto"),
	[]byte("estafa"),
	[]byte("maltrato"),
	[]byte("falso"),
}

const (
	// Tiempo máximo para esperar escribir un mensaje al cliente
	writeWait = 10 * time.Second
	// Tiempo máximo para recibir el pong del cliente (heartbeat)
	pongWait = 60 * time.Second
	// Intervalo para enviar pings y mantener la conexión viva
	pingPeriod = (pongWait * 9) / 10
	// Tamaño máximo del mensaje (evitar ataques de memoria)
	maxMessageSize = 512
)

// Client es un intermediario entre el websocket connection y el Hub
type Client struct {
	Hub *Hub
	// La conexión WebSocket real
	Conn *websocket.Conn
	// Canal bufferizado para mensajes salientes
	Send chan []byte
	// ID del usuario (para saber quién es)
	UserID string
}

func (c *Client) ReadPump() {
	defer func() {
		c.Hub.Unregister <- c
		c.Conn.Close()
	}()
	
	c.Conn.SetReadLimit(maxMessageSize)
	_ = c.Conn.SetReadDeadline(time.Now().Add(pongWait))
	c.Conn.SetPongHandler(func(string) error { 
    _ = c.Conn.SetReadDeadline(time.Now().Add(pongWait)) 
    return nil 
})
	
	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("error: %v", err)
			}
			break
		}

		// --- NUEVO: Filtro de Seguridad (R-SEC-05) ---
		// Normalizamos el mensaje (minúsculas y quitando espacios extras)
		message = bytes.TrimSpace(bytes.Replace(message, []byte{'\n'}, []byte{' '}, -1))
		
		if containsBadWords(message) {
			// Opción A: Bloquear silenciosamente (Shadowban)
			log.Printf(" ALERTA: Usuario %s intentó enviar contenido prohibido: %s", c.UserID, message)
			
			// Opción B: Avisar al usuario (Le enviamos un mensaje de sistema solo a él)
			errorMessage := []byte(" Mensaje bloqueado por el sistema de seguridad 'Evil PAWS'.")
			
			// Escribimos directamente en su canal de salida para que solo él lo vea
			select {
			case c.Send <- errorMessage:
			default:
				close(c.Send)
				delete(c.Hub.Clients, c)
			}
			
			// Importante: NO enviamos el mensaje al Hub, aquí muere.
			continue 
		}
		// ----------------------------------------------

		c.Hub.Broadcast <- message
	}
}

func containsBadWords(message []byte) bool {
	lowerMsg := bytes.ToLower(message)
	for _, word := range badWords {
		if bytes.Contains(lowerMsg, word) {
			return true
		}
	}
	return false
}

// WritePump bombea mensajes del Hub al websocket (Salida)
// Se ejecuta en su propia goroutine
func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()
	
	for {
		select {
		case message, ok := <-c.Send:
			_ = c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// El Hub cerró el canal
				_ = c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			_, _ = w.Write(message)

			// Agregar mensajes en cola al mismo paquete TCP si es posible (optimización)
			n := len(c.Send)
			for i := 0; i < n; i++ {
				_, _ = w.Write([]byte{'\n'})
				_, _ = w.Write(<-c.Send)
			}

			if err := w.Close(); err != nil {
				return
			}
		
		case <-ticker.C:
			// Heartbeat para mantener viva la conexión
			_ = c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}