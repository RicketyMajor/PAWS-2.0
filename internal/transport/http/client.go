package http

import (
	"github.com/gorilla/websocket"
)

// Client es un intermediario entre el websocket y el hub.
type Client struct {
	hub *Hub

	// La conexión websocket real
	conn *websocket.Conn

	// Canal para mensajes salientes (buffered)
	send chan []byte
	
	// ID del usuario (Útil para saber quién envió el mensaje)
	userID uint
}