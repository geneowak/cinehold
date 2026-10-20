-- +goose Up
ALTER TABLE
    movies
ADD
    COLUMN poster_image_url TEXT;

-- +goose Down
ALTER TABLE
    movies DROP COLUMN poster_image_url;
