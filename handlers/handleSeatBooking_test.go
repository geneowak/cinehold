package handlers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/geneowak/cinehold/internal/database"
	"github.com/geneowak/cinehold/internal/testdb"
	"github.com/geneowak/cinehold/internal/types"
	"github.com/google/uuid"
)

/**
 * Sends the same reservation id twice. Both copies pass the availability
 * pre check, the first UPDATE books the seat and the second finds it no longer
 * available, so the handler must roll the whole batch back.
 */
func TestApiConfig_handleSeatBooking_RollsBackWholeBatch(t *testing.T) {
	conn := testdb.OpenAndMigrate(t)
	if conn == nil {
		t.Skip("TEST_DB_URL not set")
	}
	scope := testdb.Begin(t, conn)
	q := scope.Queries
	ctx := context.Background()

	loc, err := q.CreateLocation(ctx, database.CreateLocationParams{
		Name:         "Test Location",
		Address:      "1 Test St",
		GoogleMapUrl: "https://maps.google.com/?q=test",
	})
	if err != nil {
		t.Fatalf("Failed to create location: %v", err)
	}

	cin, err := q.CreateCinema(ctx, database.CreateCinemaParams{
		Name:            "Test Cinema",
		LocationID:      loc.ID,
		ExperienceTypes: types.StringSlice{"IMAX"},
		SeatMap:         types.SeatMap{},
	})
	if err != nil {
		t.Fatalf("Failed to create cinema: %v", err)
	}

	mov, err := q.CreateMovie(ctx, database.CreateMovieParams{
		Name:            "Test Movie",
		Description:     "A movie that only exists for testing purposes",
		DurationInMins:  120,
		TrailerUrl:      "https://example.com/trailer",
		Genre:           types.StringSlice{"Action"},
		PgRating:        "PG-13",
		ExperienceTypes: types.StringSlice{"IMAX"},
	})
	if err != nil {
		t.Fatalf("Failed to create movie: %v", err)
	}

	now := time.Now().UTC()
	showTime, err := q.CreateShowTime(ctx, database.CreateShowTimeParams{
		StartTime:      now,
		Price:          5000,
		MovieID:        mov.ID,
		CinemaID:       cin.ID,
		ExperienceType: "IMAX",
		StartDate:      now.Add(-time.Hour),
		EndDate:        now.Add(time.Hour),
	})
	if err != nil {
		t.Fatalf("Failed to create show time: %v", err)
	}

	usr, err := q.CreateUser(ctx, database.CreateUserParams{
		Email:          uuid.NewString() + "@test.com",
		HashedPassword: "hashed",
	})
	if err != nil {
		t.Fatalf("Failed to create user: %v", err)
	}

	res, err := q.CreateReservation(ctx, database.CreateReservationParams{
		UserID:     usr.ID,
		SeatNo:     "A:1",
		ShowTimeID: showTime.ID,
	})
	if err != nil {
		t.Fatalf("Failed to create reservation: %v", err)
	}

	cfg := newTestApiConfigWithPool(q, scope.Beginner)

	body := fmt.Sprintf(`{"seat_reservations": ["%s", "%s"]}`, res.ID, res.ID)
	req := httptest.NewRequest(http.MethodPost, "/api/seats/book", strings.NewReader(body))
	req = req.WithContext(context.WithValue(ctx, "user_id", usr.ID))
	rec := httptest.NewRecorder()

	cfg.handleSeatBooking(rec, req)

	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want %d; body: %s", rec.Code, http.StatusUnprocessableEntity, rec.Body.String())
	}

	// the first UPDATE must have been rolled back along with the second's failure
	got, err := q.GetUserBookingById(ctx, database.GetUserBookingByIdParams{
		ID:     res.ID,
		UserID: usr.ID,
		Status: "available",
	})
	if err != nil {
		t.Fatalf("Reservation should still be available after rollback: %v", err)
	}
	if got.Status != "available" {
		t.Errorf("status = %q, want %q", got.Status, "available")
	}
}
