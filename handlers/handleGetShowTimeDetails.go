package handlers

import (
	"errors"
	"net/http"

	"github.com/geneowak/cinehold/internal/database"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func (cfg *ApiConfig) handleGetShowTimeDetails(w http.ResponseWriter, r *http.Request) {
	idParam := r.PathValue("showTimeId")
	showTimeId, err := uuid.Parse(idParam)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid show time id", err)
		return
	}

	// get logged in user and see if they are an admin or not
	userId, _ := GetUserIdFromContext(r.Context())
	authUser, err := cfg.DB.GetUserById(r.Context(), userId)
	// the only err that can happen here is a db error because we've already validated that the user exists
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Error validating user", err)
		return
	}

	details, err := cfg.DB.GetShowTimeDetails(r.Context(), showTimeId)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			respondWithError(w, http.StatusNotFound, "Show time not found", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Error fetching show time details", err)
		return
	}

	// we return here for none admin users
	if !authUser.IsAdmin {
		type response struct {
			database.ShowTime
			Cinema database.Cinema `json:"cinema"`
		}

		respondWithJSON(w, http.StatusOK, response{details.ShowTime, details.Cinema})
		return
	}

	showTime := details.ShowTime
	cinema := details.Cinema

	//get current bookings
	bookings, err := cfg.DB.GetShowTimeReservations(r.Context(), database.GetShowTimeReservationsParams{
		ShowTimeID: showTime.ID,
		Status:     "booked",
	})
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			respondWithError(w, http.StatusInternalServerError, "Error fetching show time bookings", err)
			return
		}
	}

	type response struct {
		database.ShowTime
		Cinema          database.Cinema `json:"cinema"`
		CinemaCapacity  int             `json:"cinema_capacity"`
		CurrentBookings int             `json:"current_bookings"`
		CurrentRevenue  int             `json:"current_revenue"`
	}

	respondWithJSON(w, http.StatusOK, response{
		ShowTime:        showTime,
		Cinema:          cinema,
		CinemaCapacity:  cinema.SeatMap.TotalSeats,
		CurrentBookings: len(bookings),
		CurrentRevenue:  len(bookings) * int(showTime.Price),
	})
}
