// Package workers contains background consumers for message queues.
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

// PushEvent defines the structure of a message consumed from the push notification queue.
type PushEvent struct {
	UserID uint   `json:"user_id"`
	Title  string `json:"title"`
	Body   string `json:"body"`
	Type   string `json:"type"`
}

// StartNotificationConsumer starts a resilient worker that consumes messages from the
// "push_notifications" queue and sends them via Firebase Cloud Messaging (FCM).
func StartNotificationConsumer(rabbitURL string, db *gorm.DB) {
	// --- Firebase Initialization ---
	projectID := os.Getenv("FIREBASE_PROJECT_ID")
	if projectID == "" {
		log.Println("WARNING: FIREBASE_PROJECT_ID not set in .env. Push notifications will be disabled.")
	}

	conf := &firebase.Config{ProjectID: projectID}
	// The GOOGLE_APPLICATION_CREDENTIALS env var should be set to the path of the service account file.
	// We set it here as a fallback if it's not present in the environment.
	if os.Getenv("GOOGLE_APPLICATION_CREDENTIALS") == "" {
		_ = os.Setenv("GOOGLE_APPLICATION_CREDENTIALS", "firebase-service-account.json")
	}

	app, err := firebase.NewApp(context.Background(), conf)
	if err != nil {
		log.Printf("Error initializing Firebase App: %v. Push notifications will not work.", err)
		return
	}

	fcmClient, err := app.Messaging(context.Background())
	if err != nil {
		log.Printf("Error getting FCM client: %v. Push notifications will not work.", err)
		return
	}

	// --- RabbitMQ Consumer ---
	rabbit.ConsumeWithRetry(rabbitURL, "push_notifications", func(body []byte) error {
		var event PushEvent
		if err := json.Unmarshal(body, &event); err != nil {
			return fmt.Errorf("error decoding push event: %v", err)
		}

		// Get the recipient's FCM token from the database.
		var user domain.User
		if err := db.Select("fcm_token").First(&user, event.UserID).Error; err != nil {
			return fmt.Errorf("user %d not found", event.UserID)
		}

		// If the user has no token, silently drop the notification.
		if user.FCMToken == "" {
			return nil
		}

		// Apply Android-specific configuration, e.g., for grouping chat notifications.
		var androidConfig *messaging.AndroidConfig
		if event.Type == "message" {
			androidConfig = &messaging.AndroidConfig{
				Notification: &messaging.AndroidNotification{
					Tag:   "chat_group", // Groups notifications on the device
					Color: "#E91E63",
				},
			}
		}

		// Send the message via FCM.
		_, err = fcmClient.Send(context.Background(), &messaging.Message{
			Token: user.FCMToken,
			Notification: &messaging.Notification{
				Title: event.Title,
				Body:  event.Body,
			},
			Android: androidConfig,
			Data: map[string]string{
				"type": event.Type, // Custom data for the client app to handle navigation
			},
		})

		return err
	})
}
