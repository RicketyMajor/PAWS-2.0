package workers

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	firebase "firebase.google.com/go"
	"firebase.google.com/go/messaging"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	rabbit "github.com/RicketyMajor/PAWS-2.0/internal/infrastructure/messaging"
	"gorm.io/gorm"
)

type PushEvent struct {
	UserID uint   `json:"user_id"`
	Title  string `json:"title"`
	Body   string `json:"body"`
	Type   string `json:"type"`
}

func StartNotificationConsumer(rabbitURL string, db *gorm.DB) {
	projectID := os.Getenv("FIREBASE_PROJECT_ID")
	if projectID == "" {
		log.Println("ADVERTENCIA: FIREBASE_PROJECT_ID no configurado en .env.")
	}

	conf := &firebase.Config{ProjectID: projectID}
	_ = os.Setenv("GOOGLE_APPLICATION_CREDENTIALS", "firebase-service-account.json")

	app, err := firebase.NewApp(context.Background(), conf)
	if err != nil {
		log.Printf("Error inicializando Firebase App: %v", err)
		return
	}

	fcmClient, err := app.Messaging(context.Background())
	if err != nil {
		log.Printf("Error obteniendo cliente FCM: %v", err)
		return
	}

	// Consumidor con auto-recovery
	rabbit.ConsumeWithRetry(rabbitURL, "push_notifications", func(body []byte) error {
		var event PushEvent
		if err := json.Unmarshal(body, &event); err != nil {
			return fmt.Errorf("error decodificando evento push: %v", err)
		}

		var user domain.User
		if err := db.Select("fcm_token").First(&user, event.UserID).Error; err != nil {
			return fmt.Errorf("usuario %d no encontrado", event.UserID)
		}

		if user.FCMToken == "" {
			return nil // Retornamos nil silenciosamente, no es fallo de infraestructura
		}

		var androidConfig *messaging.AndroidConfig
		if event.Type == "message" {
			androidConfig = &messaging.AndroidConfig{
				Notification: &messaging.AndroidNotification{
					Tag:   "chat_group",
					Color: "#E91E63",
				},
			}
		}

		_, err = fcmClient.Send(context.Background(), &messaging.Message{
			Token: user.FCMToken,
			Notification: &messaging.Notification{
				Title: event.Title,
				Body:  event.Body,
			},
			Android: androidConfig,
			Data: map[string]string{
				"type": event.Type,
			},
		})

		return err
	})
}
