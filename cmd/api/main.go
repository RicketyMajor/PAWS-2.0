package main

import (
	"log"
	"os"

	"github.com/RicketyMajor/PAWS-2.0/internal/platform/database" // ⚠️ IMPORTANTE: Cambia TU_USUARIO por tu usuario de GitHub real
	"github.com/joho/godotenv"
)

func main() {
	// 1. Cargar variables de entorno desde el archivo .env
	// Esto debe ser LO PRIMERO que se ejecute.
	if err := godotenv.Load(); err != nil {
		log.Fatal("Error cargando el archivo .env")
	}

	// 2. Conectar a la Base de Datos
	database.Connect()

	// 3. Simulación de inicio del servidor
	port := os.Getenv("PORT")
	log.Printf("🚀 Servidor PAWS corriendo en el puerto %s", port)
	
	// Aquí, más adelante, pondremos el código que mantiene el servidor "escuchando" peticiones.
	// Por ahora, el programa terminará después de imprimir esto.
}