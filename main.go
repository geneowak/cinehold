package main

import (
	"context"
	"log"
	"os"

	"github.com/geneowak/cinehold/handlers"
	"github.com/geneowak/cinehold/internal/database"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

func main() {
	godotenv.Load()
	dbUrl := os.Getenv("DB_URL")
	if dbUrl == "" {
		log.Fatal("DB_URL env variable has not been set")
	}
	platform := os.Getenv("PLATFORM")
	if platform == "" {
		log.Fatal("PLATFORM env variable has not been set")
	}
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		log.Fatal("JWT_SECRET env variable has not been set")
	}

	db, err := pgxpool.New(context.Background(), dbUrl)
	if err != nil {
		log.Fatal("Failed to open the DB", err)
	}
	const filePathRoot string = "."
	port := "8080"
	if envPort := os.Getenv("PORT"); envPort != "" {
		port = envPort
	}
	/** we use a single validate instance of this because of
	* 1. heavy initialization cost
	* 2. it is thread safe and so can be used simultaneously
	* 3. when we add custom registrations, they'll be carried through to all users
	**/

	cfg := handlers.ApiConfig{
		DB:        database.New(db),
		Pool:      db,
		Platform:  platform,
		JwtSecret: jwtSecret,
	}
	validate := handlers.CreateValidator(&cfg)
	cfg.Validate = validate

	server := handlers.SetupServer(&cfg, filePathRoot, port)

	log.Println("Listening on port:", port)
	log.Fatal(server.ListenAndServe())
}
