-- name: CreateReservation :one
INSERT INTO
    reservations(
        id,
        user_id,
        seat_no,
        show_time_id,
        reserved_at,
        created_at,
        updated_at
    )
VALUES
    (uuidv7(), $1, $2, $3, NOW(), NOW(), NOW())
RETURNING
    *;

-- name: GetReservationBySeatNo :one
SELECT
    *
FROM
    reservations
WHERE
    show_time_id = $1
    AND seat_no = $2
LIMIT
    1;

-- name: UpdateReservation :one
UPDATE
    reservations
SET
    user_id = $1,
    reserved_at = NOW()
WHERE
    seat_no = $2
    AND show_time_id = $3
RETURNING
    *;

-- name: MarkReservationBooked :one
UPDATE
    reservations
SET
    STATUS = 'booked',
    reserved_at = NULL
WHERE
    id = $1
    AND user_id = $2
    AND STATUS = 'available'
RETURNING
    *;

-- name: GetUserBookings :many
SELECT
    *
FROM
    reservations
WHERE
    STATUS = 'booked'
    AND user_id = $1;

-- name: GetUserBookingById :one
SELECT
    *
FROM
    reservations
WHERE
    STATUS = $3
    AND id = $1
    AND user_id = $2
LIMIT
    1;

-- name: DeleteUserBooking :exec
DELETE FROM
    reservations
WHERE
    id = $1
    AND user_id = $2;

-- name: GetShowTimeReservations :many
SELECT
    *
FROM
    reservations
WHERE
    show_time_id = $1
    AND STATUS = $2;

-- name: GetShowTimeBookedSeats :many
SELECT
    seat_no
FROM
    reservations
WHERE
    (
        STATUS = 'booked'
        OR reserved_at > $2
    )
    AND show_time_id = $1;
