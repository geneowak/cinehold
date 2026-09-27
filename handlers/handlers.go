package handlers

import (
	"net/http"
	"time"
)

func SetupServer(cfg *ApiConfig, filePathRoot, port string) *http.Server {
	mux := http.NewServeMux()

	mux.HandleFunc("POST /api/auth/signup", cfg.handleUserSignup)

	mux.HandleFunc("POST /api/auth/login", cfg.handleLogin)

	mux.HandleFunc("POST /api/auth/refresh", cfg.handleRefreshToken)
	mux.HandleFunc("POST /api/auth/revoke", cfg.handleRevokeToken)

	// Admin routes
	mux.HandleFunc("PUT /api/users/{userId}", cfg.middlewareAdminAuth(cfg.handleUpdateAdminStatus))

	mux.HandleFunc("POST /api/movies", cfg.middlewareAdminAuth(cfg.handleCreateMovie))
	mux.HandleFunc("POST /api/movies/{movieId}/show-times", cfg.middlewareAdminAuth(cfg.handleCreateMovieShowTime))
	mux.HandleFunc("GET /api/admin/movies", cfg.middlewareAdminAuth(cfg.handleAdminShowMovies))
	mux.HandleFunc("PUT /api/movies/{movieId}", cfg.middlewareAdminAuth(cfg.handleUpdateMovieDetails))
	mux.HandleFunc("DELETE /api/movies/{movieId}", cfg.middlewareAdminAuth(cfg.handleDeleteMovie))

	mux.HandleFunc("GET /api/show-times/{showTimeId}", cfg.middlewareAdminAuth(cfg.handleGetShowTimeDetails))

	mux.HandleFunc("POST /api/locations", cfg.middlewareAdminAuth(cfg.handleCreateLocation))
	mux.HandleFunc("GET /api/locations", cfg.middlewareAdminAuth(cfg.handleGetLocations))
	mux.HandleFunc("GET /api/locations/{locationId}", cfg.middlewareAdminAuth(cfg.handleGetLocationDetails))

	mux.HandleFunc("POST /api/cinemas", cfg.middlewareAdminAuth(cfg.handleCreateCinema))
	mux.HandleFunc("PUT /api/cinemas/{cinemaId}", cfg.middlewareAdminAuth(cfg.handleUpdateCinemaDetails))

	// user routes
	mux.HandleFunc("GET /api/movies", cfg.middlewareAuth(cfg.handleGetMovies))
	mux.HandleFunc("GET /api/movies/{movieId}", cfg.middlewareAuth(cfg.handleGetMovieDetails))

	mux.HandleFunc("POST /api/seats/reserve", cfg.middlewareAuth(cfg.handleReserveSeat))
	mux.HandleFunc("POST /api/seats/book", cfg.middlewareAuth(cfg.handleSeatBooking))
	mux.HandleFunc("GET /api/bookings", cfg.middlewareAuth(cfg.handleGetBookings))
	mux.HandleFunc("DELETE /api/bookings/{reservationId}", cfg.middlewareAuth(cfg.handleDeleteBooking))

	mux.HandleFunc("GET /api/show-times/{showTimeId}/booked-seats", cfg.middlewareAuth(cfg.handleGetShowTimeBookedSeats))

	return &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}
}
