-- +goose Up
CREATE TABLE show_times(
    id UUID PRIMARY KEY,
    start_time TIME NOT NULL,
    price INT NOT NULL,
    description VARCHAR(100),  -- premier, etc..
    price_currency VARCHAR(5) NOT NULL DEFAULT 'UGX',
    movie_id UUID NOT NULL REFERENCES movies(id) ON DELETE CASCADE,
    cinema_id UUID NOT NULL REFERENCES cinemas(id) ON DELETE CASCADE,
    experience_type TEXT NOT NULL,
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- +goose Down
DROP TABLE show_times;
