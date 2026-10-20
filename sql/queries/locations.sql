-- name: CreateLocation :one
INSERT INTO
    locations(
        id,
        name,
        address,
        google_map_url
    )
VALUES
    (uuidv7(), $1, $2, $3)
RETURNING
    *;

-- name: GetLocations :many
SELECT
    *
FROM
    locations;

-- name: GetLocationDetails :one
SELECT
    locations.*,
    COALESCE(c_agg.venues, '[]'::jsonb) AS cinemas
FROM
    locations
    LEFT JOIN LATERAL(
        SELECT
            jsonb_agg(
                to_jsonb(c)
                ORDER BY
                    c.created_at
            ) AS venues
        FROM
            cinemas c
        WHERE
            c.location_id = locations.id
    ) c_agg ON TRUE
WHERE
    locations.id = $1;
