-- +goose Up
CREATE TABLE movies(
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    duration_in_mins INT NOT NULL,
    trailer_url TEXT NOT NULL,
    genre TEXT NOT NULL,
    pg_rating VARCHAR(255) NOT NULL,
    experience_types TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- +goose Down
DROP TABLE movies;
