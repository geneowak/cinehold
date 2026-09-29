package handlers

import (
	"context"

	"github.com/geneowak/cinehold/internal/database"
	"github.com/go-playground/validator/v10"
	"github.com/jackc/pgx/v5"
)

// TxBeginner is the minimal surface needed to start a transaction.
// Both *pgxpool.Pool and *pgx.Conn satisfy it.
type TxBeginner interface {
	Begin(ctx context.Context) (pgx.Tx, error)
}

type ApiConfig struct {
	DB        database.Querier
	Pool      TxBeginner
	Platform  string
	JwtSecret string
	Validate  *validator.Validate
}
