package handlers

import (
	"net/http"
	"time"

	"github.com/geneowak/cinehold/internal/database"
	"github.com/google/uuid"
)

/**
* This is the endpoint that will be polled by the ui when the user is viewing
* the seats available and trying to make a booking, the front end will already have the
* cinema details which has the seat map and so this will only return the booked and reserved seats
**/
func (cfg *ApiConfig) handleGetShowTimeBookedSeats(w http.ResponseWriter, r *http.Request) {
	// check seats that are currently booked or reserved
	idParam := r.PathValue("showTimeId")
	showTimeId, err := uuid.Parse(idParam)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid show time id", err)
		return
	}

	timeLimit := time.Now().Add(-10 * time.Minute)
	bookedSeats, err := cfg.DB.GetShowTimeBookedSeats(r.Context(), database.GetShowTimeBookedSeatsParams{
		ShowTimeID: showTimeId,
		ReservedAt: &timeLimit,
	})
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Error fetching booked seats", err)
		return
	}

	respondWithJSON(w, http.StatusOK, bookedSeats)
}
