package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/geneowak/cinehold/internal/database"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type seatBookingRequest struct {
	SeatReservations []string `json:"seat_reservations" validate:"required,dive,uuid_rfc4122"`
}

func (cfg *ApiConfig) handleSeatBooking(w http.ResponseWriter, r *http.Request) {
	var req seatBookingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		handleJsonDecodeError(w, err)
		return
	}

	if err := cfg.Validate.Struct(req); err != nil {
		handleValidationErrors(w, err)
		return
	}

	userId, _ := GetUserIdFromContext(r.Context())

	errorMsgs := map[string][]string{}
	for i, id := range req.SeatReservations {
		// no error is expected here because we validated that they are uuids
		bookingId, _ := uuid.Parse(id)
		// bookings can only be made on non booked reservations that the user owns
		_, err := cfg.DB.GetUserBookingById(r.Context(), database.GetUserBookingByIdParams{
			ID:     bookingId,
			Status: "available",
			UserID: userId,
		})
		if err != nil {
			field := fmt.Sprintf("seat_reservations[%v]", i)
			if errors.Is(err, pgx.ErrNoRows) {
				errorMsgs[field] = append(errorMsgs[field], "Seat Reservation not found.")
			} else {
				errorMsgs[field] = append(errorMsgs[field], "Error checking seat reservation.")
			}
		}
	}
	if len(errorMsgs) > 0 {
		respondWithValidationErrors(w, errorMsgs)
		return
	}

	tx, err := cfg.Pool.Begin(r.Context())
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Error creating reservation", err)
		return
	}
	// no-op once committed; WithoutCancel so a canceled request still rolls back
	defer tx.Rollback(context.WithoutCancel(r.Context()))

	// *pgx.Tx satisfies database.DBTX, so we can bind a Querier to the tx
	q := database.New(tx)

	response := []database.Reservation{}
	for i, stringId := range req.SeatReservations {
		reservationId, _ := uuid.Parse(stringId)
		reservation, err := q.MarkReservationBooked(r.Context(), database.MarkReservationBookedParams{
			ID:     reservationId,
			UserID: userId,
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				// booked by someone else first; keep collecting so the client
				// sees every conflicting seat, not just the first
				field := fmt.Sprintf("seat_reservations[%v]", i)
				errorMsgs[field] = append(errorMsgs[field], "Seat Reservation not found.")
				continue
			}
			// returning here rolls back every seat booked so far in this loop
			respondWithError(w, http.StatusInternalServerError, "Error creating reservation", err)
			return
		}
		response = append(response, reservation)
	}

	// someone else got there first — roll back the whole batch
	if len(errorMsgs) > 0 {
		respondWithValidationErrors(w, errorMsgs)
		return
	}

	if err := tx.Commit(r.Context()); err != nil {
		respondWithError(w, http.StatusInternalServerError, "Error creating reservation", err)
		return
	}

	respondWithJSON(w, http.StatusOK, response)
}
