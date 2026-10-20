-- name: CreateMovie :one
INSERT INTO
    movies(
        id,
        name,
        description,
        duration_in_mins,
        trailer_url,
        genre,
        pg_rating,
        experience_types
    )
VALUES
    (
        uuidv7(),
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7
    )
RETURNING
    *;

-- name: GetMovieById :one
SELECT
    *
FROM
    movies
WHERE
    id = $1;

-- name: CheckMovieById :one
SELECT
    EXISTS(
        SELECT
            1
        FROM
            movies
        WHERE
            id = $1
    );

-- name: GetMovieDetails :one
SELECT
    movies.*,
    COALESCE(st_agg.show_times, '[]'::jsonb) AS show_times
FROM
    movies
    LEFT JOIN LATERAL(
        SELECT
            jsonb_agg(
                to_jsonb(st)
                ORDER BY
                    st.start_date,
                    st.start_time
            ) AS show_times
        FROM
            show_times st
        WHERE
            st.movie_id = movies.id
    ) st_agg ON TRUE
WHERE
    movies.id = $1;

-- name: UpdateMovieDetails :one
UPDATE
    movies
SET
    name = $1,
    description = $2,
    duration_in_mins = $3,
    trailer_url = $4,
    genre = $5,
    pg_rating = $6,
    experience_types = $7,
    updated_at = NOW()
WHERE
    id = $8
RETURNING
    *;

-- name: GetMovieOngoingShowtimes :one
SELECT
    movies.*,
    COALESCE(st_agg.show_times, '[]'::jsonb) AS show_times
FROM
    movies
    LEFT JOIN LATERAL(
        SELECT
            jsonb_agg(
                to_jsonb(st)
                ORDER BY
                    st.end_date
            ) AS show_times
        FROM
            show_times st
        WHERE
            st.end_date >= $2
            AND st.movie_id = movies.id
    ) st_agg ON TRUE
WHERE
    movies.id = $1;

-- name: DeleteMovie :exec
DELETE FROM
    movies
WHERE
    id = $1;
