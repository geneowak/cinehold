-- +goose Up
ALTER TABLE
    reservations
ADD
    CONSTRAINT unx_show_time_seat_no UNIQUE(show_time_id, seat_no);

-- +goose Down
ALTER TABLE
    reservations DROP CONSTRAINT unx_show_time_seat_no;
