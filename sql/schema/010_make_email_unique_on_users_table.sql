-- +goose Up
ALTER TABLE
    users
ADD
    CONSTRAINT unx_user_email UNIQUE (email);

-- +goose Down
ALTER TABLE
    users DROP CONSTRAINT unx_user_email;
