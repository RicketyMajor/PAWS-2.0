// Package services contains the core business logic of the application.
package services

import (
	"errors"
	"fmt"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// =========================================================================
// Service Definition & Constants
// =========================================================================

// Local constants mapped to domain MatchStatus for convenience.
const (
	MatchAdopterLeft = domain.MatchAdopterLeft
	MatchRescuerLeft = domain.MatchRescuerLeft
	MatchPetDeleted  = domain.MatchPetDeleted
	MatchCancelled   = domain.MatchCancelled
	MatchAccepted    = domain.MatchAccepted
)

// MatchService provides business logic for pet matching operations.
type MatchService struct {
	db         *gorm.DB
	petService *PetService
}

// NewMatchService creates a new MatchService.
func NewMatchService(db *gorm.DB, petService *PetService) *MatchService {
	return &MatchService{
		db:         db,
		petService: petService,
	}
}

// =========================================================================
// Core Matching Logic
// =========================================================================

// GetSwipeDeck returns available pets for an adopter, filtering out already seen pets and their own pets.
func (s *MatchService) GetSwipeDeck(userID uint, lat, lon float64) ([]domain.Pet, error) {
	// 1. Get the current user's RUN to prevent them from seeing their own pets.
	var currentUser domain.User
	if err := s.db.Select("run").First(&currentUser, userID).Error; err != nil {
		return nil, fmt.Errorf("error identifying user: %v", err)
	}

	// 2. Read the adopter's profile. It drives the ordering below.
	// Most users have never filled it in, and for them there is no row at all. That is
	// not a failure, so the error is dropped — but it is also not the same as a profile
	// full of falses: an absent profile means "unknown", while has_yard = false means
	// "no yard", and only the second should push a pet that needs a yard down the deck.
	// With no profile the score is left out of the query entirely and the deck orders
	// exactly as it did before profiles entered it.
	var profile domain.UserProfile
	hasProfile := s.db.Where("user_id = ?", userID).First(&profile).Error == nil

	var pets []domain.Pet

	// 3. Build the query.
	query := s.db.Table("pets p").
		Select("p.*").
		Joins("INNER JOIN users u ON p.user_id = u.id"). // Join to filter by owner's RUN
		Joins("LEFT JOIN matches m ON m.pet_id = p.id AND m.adopter_id = ?", userID). // Join to check for previous interactions
		Where("m.id IS NULL"). // Filter out pets the user has already swiped on.
		Where("p.status = ?", domain.StatusAvailable).
		Where("p.deleted_at IS NULL").
		Where("u.run <> ?", currentUser.Run) // "Mirror Filter": Don't show user's own pets.

	// 4. Order by fit first, then distance. Both criteria go into ONE expression on
	// purpose: gorm's Order only understands clause.OrderBy, clause.OrderByColumn and
	// string — a bare clause.Expr matches no case and is dropped without a word — and
	// clause.OrderBy builds its Expression and ignores everything else, so a second
	// Order call would silently replace the first rather than follow it.
	//
	// The score runs 0-4: one point for every need this adopter's home can meet. Pets
	// that do not fit are ranked last, never hidden. With a handful of pets published a
	// hard filter would empty the deck, and an empty deck is indistinguishable from a
	// broken one.
	var orderSQL string
	var orderVars []interface{}
	if hasProfile {
		fit := fitFromProfile(profile)
		orderSQL = `(
		CASE WHEN p.requires_yard AND NOT ? THEN 0 ELSE 1 END +
		CASE WHEN ? AND NOT p.good_with_kids THEN 0 ELSE 1 END +
		CASE WHEN ? AND NOT p.good_with_dogs THEN 0 ELSE 1 END +
		CASE WHEN ? AND NOT p.good_with_cats THEN 0 ELSE 1 END) DESC, `
		orderVars = append(orderVars, fit.hasYard, fit.hasKids, fit.hasDogs, fit.hasCats)
	}

	// 5. Distance breaks ties, or creation date when the client sent no location.
	if lat != 0 && lon != 0 {
		orderSQL += `((? - p.latitude) * (? - p.latitude) + (? - p.longitude) * (? - p.longitude)) ASC`
		orderVars = append(orderVars, lat, lat, lon, lon)
	} else {
		orderSQL += `p.created_at DESC`
	}
	query = query.Order(clause.OrderBy{Expression: clause.Expr{SQL: orderSQL, Vars: orderVars}})

	// 6. Execute and preload data for the UI.
	err := query.Preload("Images").Preload("User").Find(&pets).Error
	return pets, err
}

// adopterFit describes what an adopter's home can take. The zero value means
// "no constraints", which every pet satisfies.
type adopterFit struct {
	hasYard bool
	hasKids bool
	hasDogs bool
	hasCats bool
}

// fitFromProfile maps the profile's stored strings onto the flags the deck scores.
// The literals are the ones edit_profile_screen.dart offers, and nothing else writes
// this table. A typo here would not fail: the deck would quietly stop ranking, which
// is why TestFitFromProfile pins every option the client can send.
func fitFromProfile(p domain.UserProfile) adopterFit {
	return adopterFit{
		hasYard: p.HasYard,
		hasKids: p.FamilyComposition == "Family w/Kids",
		hasDogs: p.OtherPets == "Dogs" || p.OtherPets == "Both",
		hasCats: p.OtherPets == "Cats" || p.OtherPets == "Both",
	}
}

// Swipe records a user's swipe action (like or dislike) on a pet.
func (s *MatchService) Swipe(adopterID, petID uint, isLike bool) error {
	status := domain.MatchPending
	if !isLike {
		status = domain.MatchRejected
	}
	var match domain.Match
	err := s.db.Where("adopter_id = ? AND pet_id = ?", adopterID, petID).First(&match).Error
	if err == nil {
		// If a record exists, update it.
		match.Status = status
		return s.db.Save(&match).Error
	}
	// Otherwise, create a new match record.
	newMatch := domain.Match{AdopterID: adopterID, PetID: petID, Status: status}
	return s.db.Create(&newMatch).Error
}

// RespondMatch allows a rescuer to accept or reject a pending match request.
func (s *MatchService) RespondMatch(rescuerID, matchID uint, accept bool) error {
	status := domain.MatchRejected
	if accept {
		status = MatchAccepted
	}
	if err := s.db.Model(&domain.Match{}).Where("id = ?", matchID).Update("status", status).Error; err != nil {
		return err
	}
	// The adopter learns of the acceptance from their matches list; there is no push.
	return nil
}

// =========================================================================
// Chat & Unmatch Logic
// =========================================================================

// Unmatch manages the state machine for leaving a chat.
func (s *MatchService) Unmatch(userID, matchID uint) error {
	var match domain.Match
	if err := s.db.Preload("Pet", func(db *gorm.DB) *gorm.DB {
		return db.Unscoped()
	}).First(&match, matchID).Error; err != nil {
		return errors.New("match not found")
	}

	if match.Status == MatchCancelled {
		return nil // Already permanently cancelled.
	}

	var newStatus domain.MatchStatus

	// State machine logic:
	if userID == match.AdopterID {
		// User is the Adopter
		if match.Status == MatchRescuerLeft || match.Status == MatchPetDeleted {
			newStatus = MatchCancelled // If the other party already left, it's a final cancellation.
		} else {
			newStatus = MatchAdopterLeft
		}
	} else if userID == match.Pet.UserID {
		// User is the Rescuer
		if match.Status == MatchAdopterLeft || match.Status == MatchPetDeleted {
			newStatus = MatchCancelled
		} else {
			newStatus = MatchRescuerLeft
		}
	} else {
		return errors.New("you do not have permission to leave this chat")
	}

	if match.Status != newStatus {
		return s.db.Model(&match).Update("status", newStatus).Error
	}
	return nil
}

// =========================================================================
// Match List Retrieval
// =========================================================================

// GetAdopterMatches retrieves active and left chats for an adopter.
func (s *MatchService) GetAcceptedMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Preload("Pet.User").
		Preload("Pet.Images").
		Preload("Pet", func(db *gorm.DB) *gorm.DB { return db.Unscoped() }).
		Where("adopter_id = ? AND status IN (?, ?, ?)",
			adopterID, MatchAccepted, MatchRescuerLeft, MatchPetDeleted).
		Order("updated_at DESC").
		Find(&matches).Error
	if err != nil { return nil, err }

	// Post-process to count unread messages and check for deleted pets.
	for i := range matches {
		if !matches[i].Pet.DeletedAt.Time.IsZero() {
			matches[i].Pet.Status = domain.PetStatus("deleted")
		}
		var count int64
		s.db.Model(&domain.Message{}).
			Where("match_id = ? AND sender_id != ? AND is_read = ?", matches[i].ID, adopterID, false).
			Count(&count)
		matches[i].UnreadCount = int(count)
	}
	return matches, nil
}

// GetRescuerMatches retrieves active and left chats for a rescuer.
func (s *MatchService) GetRescuerMatches(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Table("matches").
		Select("matches.*").
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").
		Preload("Pet.Images").
		Preload("Pet", func(db *gorm.DB) *gorm.DB { return db.Unscoped() }).
		Where("pets.user_id = ? AND matches.status IN (?, ?, ?)",
			rescuerID, MatchAccepted, MatchAdopterLeft, MatchPetDeleted).
		Order("matches.updated_at DESC").
		Find(&matches).Error
	if err != nil { return nil, err }
	
	// Post-process to count unread messages and check for deleted pets.
	for i := range matches {
		if !matches[i].Pet.DeletedAt.Time.IsZero() {
			matches[i].Pet.Status = domain.PetStatus("deleted")
		}
		var count int64
		s.db.Model(&domain.Message{}).
			Where("match_id = ? AND sender_id != ? AND is_read = ?", matches[i].ID, rescuerID, false).
			Count(&count)
		matches[i].UnreadCount = int(count)
	}
	return matches, nil
}

// GetAdopterPendingMatches retrieves matches that the adopter has initiated but the rescuer has not yet responded to.
func (s *MatchService) GetAdopterPendingMatches(adopterID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Preload("Pet.Images").Preload("Pet").
		Where("adopter_id = ? AND status = ?", adopterID, domain.MatchPending).
		Order("created_at DESC").
		Find(&matches).Error
	return matches, err
}

// GetPendingRequests retrieves matches that are waiting for the rescuer's response.
func (s *MatchService) GetPendingRequests(rescuerID uint) ([]domain.Match, error) {
	var matches []domain.Match
	err := s.db.Table("matches").
		Select("matches.*").
		Joins("JOIN pets ON matches.pet_id = pets.id").
		Preload("Adopter").Preload("Pet.Images").Preload("Pet").
		Where("pets.user_id = ? AND matches.status = ?", rescuerID, domain.MatchPending).
		Order("matches.created_at DESC").
		Find(&matches).Error
	return matches, err
}
