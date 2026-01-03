package workers

import (
	"context"
	"encoding/json"
	"log"
	"os"

	firebase "firebase.google.com/go"
	"firebase.google.com/go/messaging"
	"google.golang.org/api/option"

	rabbit "github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/services"
	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
)

// StartNotificationConsumer escucha la cola "push_notifications"
func StartNotificationConsumer(mq *rabbit.RabbitMQClient, db *gorm.DB) {
	// 1. Configuración Explícita
	projectID := os.Getenv("FIREBASE_PROJECT_ID")
	if projectID == "" {
		log.Println("ADVERTENCIA: FIREBASE_PROJECT_ID no configurado en .env. Las notificaciones podrían fallar.")
	}

	conf := &firebase.Config{ProjectID: projectID}
	
	// Cargar credenciales
	opt := option.WithCredentialsFile("firebase-service-account.json")
	
	// Inicializar App con Configuración explícita
	app, err := firebase.NewApp(context.Background(), conf, opt)
	if err != nil {
		log.Printf("Error inicializando Firebase en Backend: %v. Las notificaciones no funcionarán.", err)
		return
	}

	fcmClient, err := app.Messaging(context.Background())
	if err != nil {
		log.Printf("Error obteniendo cliente FCM: %v", err)
		return
	}

	// 2. Conectar a RabbitMQ
	ch := mq.GetChannel()
	// Declaramos la cola por seguridad
	_, err = ch.QueueDeclare(
		"push_notifications", // nombre
		true,                 // durable
		false,                // delete when unused
		false,                // exclusive
		false,                // no-wait
		nil,                  // arguments
	)
	
	msgs, err := ch.Consume(
		"push_notifications",
		"", false, false, false, false, nil,
	)
	if err != nil {
		log.Printf("Error consumiendo cola push: %v", err)
		return
	}

	log.Println("Worker de Notificaciones Push iniciado y conectado a Firebase.")

	go func() {
		for d := range msgs {
			var event services.NotificationEvent
			if err := json.Unmarshal(d.Body, &event); err != nil {
				log.Printf("Error decodificando evento push: %v", err)
				d.Ack(false)
				continue
			}

			// 3. Buscar el Token FCM del usuario en la BD
			var user domain.User
			if err := db.Select("fcm_token").First(&user, event.UserID).Error; err != nil {
				log.Printf("Usuario %d no encontrado o sin token", event.UserID)
				d.Ack(false)
				continue
			}

			if user.FCMToken == "" {
				d.Ack(false)
				continue
			}

			// --- LÓGICA ESTILO WHATSAPP (Agrupación) ---
			var androidConfig *messaging.AndroidConfig
			
			// Si el evento es de tipo "message" (Chat), configuramos el TAG
			if event.Type == "message" {
				androidConfig = &messaging.AndroidConfig{
					Notification: &messaging.AndroidNotification{
						Tag:   "chat_group", // <--- ESTA ES LA CLAVE: Agrupa las notificaciones
						Color: "#E91E63",    // Color rosado PAWS para el ícono pequeño/led
					},
				}
			}
			// ---------------------------------------------

			// 4. Enviar a Firebase
			_, err = fcmClient.Send(context.Background(), &messaging.Message{
				Token: user.FCMToken,
				Notification: &messaging.Notification{
					Title: event.Title,
					Body:  event.Body,
				},
				Android: androidConfig, // Inyectamos la configuración aquí
				Data: map[string]string{
					"type": event.Type, 
				},
			})

			if err != nil {
				log.Printf("Error enviando a FCM: %v", err)
			} else {
				log.Printf("Notificación enviada a usuario %d: %s", event.UserID, event.Title)
			}
			
			d.Ack(false)
		}
	}()
}