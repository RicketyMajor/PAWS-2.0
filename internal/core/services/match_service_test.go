// Package services_test contains unit tests for the services package.
package services

import (
	"testing"

	"github.com/RicketyMajor/PAWS-2.0/internal/core/domain"
	"github.com/glebarez/sqlite"
	"gorm.io/gorm"
)

// TestFitFromProfile pins the literals the Flutter client writes into user_profiles.
// The deck ranks on these flags, and a mismatch would not fail anything: the score
// would just come out flat and the deck would silently fall back to distance. That is
// the failure this test exists to catch, so every option edit_profile_screen.dart
// offers appears here by name.
func TestFitFromProfile(t *testing.T) {
	cases := []struct {
		name    string
		profile domain.UserProfile
		want    adopterFit
	}{
		{
			name:    "no profile row at all means no constraints",
			profile: domain.UserProfile{},
			want:    adopterFit{},
		},
		{
			name:    "Single lives with no kids and no pets",
			profile: domain.UserProfile{FamilyComposition: "Single", OtherPets: "None"},
			want:    adopterFit{},
		},
		{
			name:    "Couple lives with no kids",
			profile: domain.UserProfile{FamilyComposition: "Couple", OtherPets: "None"},
			want:    adopterFit{},
		},
		{
			name:    "Seniors live with no kids",
			profile: domain.UserProfile{FamilyComposition: "Seniors", OtherPets: "None"},
			want:    adopterFit{},
		},
		{
			name:    "Family w/Kids is the only composition that means kids",
			profile: domain.UserProfile{FamilyComposition: "Family w/Kids", OtherPets: "None"},
			want:    adopterFit{hasKids: true},
		},
		{
			name:    "Dogs means dogs only",
			profile: domain.UserProfile{FamilyComposition: "Single", OtherPets: "Dogs"},
			want:    adopterFit{hasDogs: true},
		},
		{
			name:    "Cats means cats only",
			profile: domain.UserProfile{FamilyComposition: "Single", OtherPets: "Cats"},
			want:    adopterFit{hasCats: true},
		},
		{
			name:    "Both means dogs and cats",
			profile: domain.UserProfile{FamilyComposition: "Single", OtherPets: "Both"},
			want:    adopterFit{hasDogs: true, hasCats: true},
		},
		{
			name:    "the yard is carried straight through",
			profile: domain.UserProfile{HasYard: true, FamilyComposition: "Single", OtherPets: "None"},
			want:    adopterFit{hasYard: true},
		},
		{
			name:    "a family with both kinds of pets and a yard",
			profile: domain.UserProfile{HasYard: true, FamilyComposition: "Family w/Kids", OtherPets: "Both"},
			want:    adopterFit{hasYard: true, hasKids: true, hasDogs: true, hasCats: true},
		},
		{
			name:    "an unknown value constrains nothing rather than guessing",
			profile: domain.UserProfile{FamilyComposition: "Familia con niños", OtherPets: "Perros"},
			want:    adopterFit{},
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := fitFromProfile(c.profile); got != c.want {
				t.Errorf("fitFromProfile(%+v)\n got %+v\nwant %+v", c.profile, got, c.want)
			}
		})
	}
}

// setupDeckDB builds a deck of three pets in its own in-memory database, rather than
// setupTestDB, whose shared cache every other test in the package reuses.
//
// created_at runs OPPOSITE to the fit score and the pets sit at different distances,
// so each ordering criterion contradicts the others. A test whose criteria agree
// passes on the fallback alone and proves nothing.
//
// ponytail: sqlite here, Postgres in production. This catches a dropped clause, a
// broken expression or an inverted comparison, not a dialect difference. The
// behavioural check against the real database is `make e2e` on a seeded deck.
func setupDeckDB(t *testing.T, name string, profile *domain.UserProfile) (*gorm.DB, uint) {
	t.Helper()

	db, err := gorm.Open(sqlite.Open("file:"+name+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal("opening the test database:", err)
	}
	if err := db.AutoMigrate(&domain.User{}, &domain.UserProfile{}, &domain.Pet{}, &domain.PetImage{}, &domain.Match{}); err != nil {
		t.Fatal("migrating the test database:", err)
	}

	adopter := domain.User{Name: "Adopter", Email: name + "-adopter@paws.cl", Run: "11.111.111-1"}
	db.Create(&adopter)
	if profile != nil {
		profile.UserID = adopter.ID
		db.Create(profile)
	}

	rescuer := domain.User{Name: "Rescuer", Email: name + "-rescuer@paws.cl", Run: "22.222.222-2"}
	db.Create(&rescuer)

	// For an adopter with kids and no yard: Best scores 4, Middle 3, Worst 2.
	db.Create(&domain.Pet{Name: "Best", UserID: rescuer.ID, Status: domain.StatusAvailable,
		RequiresYard: false, GoodWithKids: true, CreatedAt: 100, Latitude: -33.6, Longitude: -70.6})
	db.Create(&domain.Pet{Name: "Middle", UserID: rescuer.ID, Status: domain.StatusAvailable,
		RequiresYard: false, GoodWithKids: false, CreatedAt: 200, Latitude: -33.5, Longitude: -70.6})
	db.Create(&domain.Pet{Name: "Worst", UserID: rescuer.ID, Status: domain.StatusAvailable,
		RequiresYard: true, GoodWithKids: false, CreatedAt: 300, Latitude: -33.4, Longitude: -70.6})

	return db, adopter.ID
}

// names returns the deck in order, for readable failures.
func names(deck []domain.Pet) []string {
	out := make([]string, len(deck))
	for i := range deck {
		out[i] = deck[i].Name
	}
	return out
}

func assertDeck(t *testing.T, deck []domain.Pet, want []string) {
	t.Helper()
	if got := names(deck); len(got) != len(want) {
		t.Fatalf("deck: got %v, want %v — the deck must rank, never hide", got, want)
	}
	for i := range want {
		if deck[i].Name != want[i] {
			t.Fatalf("deck order: got %v, want %v", names(deck), want)
		}
	}
}

// TestSwipeDeckRanksByFit is the feature: pets whose needs this adopter's home can
// meet come first. created_at would produce the exact reverse.
func TestSwipeDeckRanksByFit(t *testing.T) {
	db, adopterID := setupDeckDB(t, "deckfit", &domain.UserProfile{
		HasYard: false, FamilyComposition: "Family w/Kids", OtherPets: "None",
	})

	deck, err := NewMatchService(db, nil, nil).GetSwipeDeck(adopterID, 0, 0)
	if err != nil {
		t.Fatal("GetSwipeDeck:", err)
	}
	assertDeck(t, deck, []string{"Best", "Middle", "Worst"})
}

// TestSwipeDeckWithoutProfileFallsBackCleanly is the safety property the design rests
// on: most users have no profile row, and for them the deck must behave exactly as it
// did before profiles entered the query — every pet present, ordered by the fallback.
func TestSwipeDeckWithoutProfileFallsBackCleanly(t *testing.T) {
	db, adopterID := setupDeckDB(t, "decknoprofile", nil)

	deck, err := NewMatchService(db, nil, nil).GetSwipeDeck(adopterID, 0, 0)
	if err != nil {
		t.Fatal("GetSwipeDeck:", err)
	}
	// No constraints, so every pet scores 4 and created_at DESC decides: newest first.
	assertDeck(t, deck, []string{"Worst", "Middle", "Best"})
}

// TestSwipeDeckBreaksTiesByDistance covers a clause that never reached the database.
// The distance ordering was passed to Order as a bare clause.Expr, which gorm drops
// without a word, so a deck built with a location had no ORDER BY at all. Here every
// pet scores the same and only distance can decide.
func TestSwipeDeckBreaksTiesByDistance(t *testing.T) {
	db, adopterID := setupDeckDB(t, "deckdistance", &domain.UserProfile{
		HasYard: true, FamilyComposition: "Single", OtherPets: "None",
	})

	// Sitting on top of Worst, the farthest from Best.
	deck, err := NewMatchService(db, nil, nil).GetSwipeDeck(adopterID, -33.4, -70.6)
	if err != nil {
		t.Fatal("GetSwipeDeck:", err)
	}
	assertDeck(t, deck, []string{"Worst", "Middle", "Best"})
}
