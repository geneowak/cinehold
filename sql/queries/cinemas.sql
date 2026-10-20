-- name: CreateCinema :one
INSERT INTO
    cinemas(
        id,
        name,
        location_id,
        experience_types,
        seat_map
    )
VALUES
    (uuidv7(), $1, $2, $3, $4)
RETURNING
    *;

-- name: CheckCinemaById :one
SELECT
    EXISTS(
        SELECT
            1
        FROM
            cinemas
        WHERE
            id = $1
    );

-- name: UpdateCinemaDetails :one
UPDATE
    cinemas
SET
    name = $1,
    experience_types = $2,
    seat_map = $3,
    updated_at = NOW()
WHERE
    id = $4
RETURNING
    *;

-- name: GetCinemaOngoingBookings :one
SELECT
    cinemas.*,
    COALESCE(st_agg.showtimes, '[]'::jsonb) AS bookings
FROM
    cinemas
    LEFT JOIN LATERAL(
        SELECT
            jsonb_agg(
                to_jsonb(st)
                ORDER BY
                    st.end_date
            ) AS showtimes
        FROM
            show_times st
        WHERE
            st.cinema_id = cinemas.id
            AND st.end_date > $2
    ) st_agg ON TRUE
WHERE
    cinemas.id = $1;
