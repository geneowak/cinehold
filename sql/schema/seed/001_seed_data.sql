-- Development seed data.
--
-- Run it after the migrations, and re-run it as often as you like:
--
--   goose -dir sql/schema/seed -no-versioning postgres "$DB_URL" up
--
-- -no-versioning keeps these statements out of goose_db_version, so they never
-- collide with the numbered migrations in sql/schema and the file can be
-- re-applied at any time. Every row uses a fixed id and ON CONFLICT DO NOTHING,
-- so running it twice is a no-op rather than a duplicate key error.
--
-- Demo accounts (throwaway credentials, safe to commit):
--   admin@cinehold.test / password123   is_admin = true
--   user@cinehold.test  / password123   is_admin = false
--
-- Showtime dates are relative to CURRENT_DATE on purpose. GetShowingMovies filters
-- on end_date >= CURRENT_DATE, so a hardcoded date would leave the seed quietly
-- unbookable once it passed. start_date and end_date are anchored at midnight rather
-- than stamped with NOW() for a second reason: the ?date= filter compares start_date
-- against a parsed YYYY-MM-DD, which is midnight, so a start_date of NOW() would sit
-- at 17:44 and never match a filter for its own day. Both columns are TIMESTAMPTZ,
-- so that midnight is UTC — which is what timezone=UTC in the DSN pins.

-- +goose Up

-- Users ---------------------------------------------------------------------
-- The password hash is argon2id for "password123" at m=65536,t=3,p=4. It is
-- generated with fixed parameters rather than hashing.DefaultParams, whose
-- Parallelism is runtime.NumCPU() and would differ per machine. CheckPasswordHash
-- reads the parameters back out of the hash, so it verifies on any hardware.
INSERT INTO users (id, email, is_admin, hashed_password)
VALUES
    (
        '00000000-0000-4000-8000-000000000001',
        'admin@cinehold.test',
        true,
        '$argon2id$v=19$m=65536,t=3,p=4$3o8YhEDF7j3AW8FQ/z5wJw$Om6ZOQ8u3bQcTE5mZ8kNNSYy3roNFpEcoOiEYTwZeKk'
    ),
    (
        '00000000-0000-4000-8000-000000000002',
        'user@cinehold.test',
        false,
        '$argon2id$v=19$m=65536,t=3,p=4$3o8YhEDF7j3AW8FQ/z5wJw$Om6ZOQ8u3bQcTE5mZ8kNNSYy3roNFpEcoOiEYTwZeKk'
    ) ON CONFLICT (id) DO NOTHING;

-- Location -------------------------------------------------------------------
INSERT INTO locations (id, name, address, google_map_url)
VALUES
    (
        '10000000-0000-4000-8000-000000000001',
        'Cinehold Grand Mall',
        '12 Reactor Road, Kampala',
        'https://maps.google.com/?q=12+Reactor+Road+Kampala'
    ) ON CONFLICT (id) DO NOTHING;

-- Cinemas --------------------------------------------------------------------
-- Two auditoriums so the admin cinema list has something to show. Screen 1 is a
-- conventional 3x8 layout; Screen 2 is smaller and mixes regular and vip seat
-- types, which the API stores but does not yet price differently.
INSERT INTO cinemas (id, location_id, name, experience_types, seat_map)
VALUES
    (
        '20000000-0000-4000-8000-000000000001',
        '10000000-0000-4000-8000-000000000001',
        'Screen 1',
        '["2D", "3D"]',
        '{
            "rows": [
                {"row": "A", "seats": [
                    {"number": 1, "type": "regular"}, {"number": 2, "type": "regular"},
                    {"number": 3, "type": "regular"}, {"number": 4, "type": "regular"},
                    {"number": 5, "type": "regular"}, {"number": 6, "type": "regular"},
                    {"number": 7, "type": "regular"}, {"number": 8, "type": "regular"}
                ]},
                {"row": "B", "seats": [
                    {"number": 1, "type": "regular"}, {"number": 2, "type": "regular"},
                    {"number": 3, "type": "regular"}, {"number": 4, "type": "regular"},
                    {"number": 5, "type": "regular"}, {"number": 6, "type": "regular"},
                    {"number": 7, "type": "regular"}, {"number": 8, "type": "regular"}
                ]},
                {"row": "C", "seats": [
                    {"number": 1, "type": "regular"}, {"number": 2, "type": "regular"},
                    {"number": 3, "type": "regular"}, {"number": 4, "type": "regular"},
                    {"number": 5, "type": "regular"}, {"number": 6, "type": "regular"},
                    {"number": 7, "type": "regular"}, {"number": 8, "type": "regular"}
                ]}
            ],
            "total_seats": 24,
            "screen": "center"
        }'::jsonb
    ),
    (
        '20000000-0000-4000-8000-000000000002',
        '10000000-0000-4000-8000-000000000001',
        'Screen 2',
        '["2D", "IMAX"]',
        '{
            "rows": [
                {"row": "A", "seats": [
                    {"number": 1, "type": "regular"}, {"number": 2, "type": "regular"},
                    {"number": 3, "type": "regular"}, {"number": 4, "type": "regular"},
                    {"number": 5, "type": "regular"}, {"number": 6, "type": "regular"}
                ]},
                {"row": "B", "seats": [
                    {"number": 1, "type": "vip"}, {"number": 2, "type": "vip"},
                    {"number": 3, "type": "vip"}, {"number": 4, "type": "vip"},
                    {"number": 5, "type": "vip"}, {"number": 6, "type": "vip"}
                ]}
            ],
            "total_seats": 12,
            "screen": "center"
        }'::jsonb
    ) ON CONFLICT (id) DO NOTHING;

-- Movies ---------------------------------------------------------------------
-- genre and experience_types are JSON arrays stored in text columns, which is what
-- the @> containment filter in GetShowingMovies runs against. Note that the match
-- is case sensitive: ?genre=Action works, ?genre=action returns nothing.
INSERT INTO movies (id, name, description, duration_in_mins, trailer_url, genre, pg_rating, experience_types)
VALUES
    (
        '30000000-0000-4000-8000-000000000001',
        'The Long Reactor',
        'A coolant engineer has eleven minutes to stop a reactor that was never meant to be restarted.',
        128,
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        '["Action", "Sci-Fi"]',
        'PG-13',
        '["2D", "3D"]'
    ),
    (
        '30000000-0000-4000-8000-000000000002',
        'Paper Harvest',
        'Two siblings return to the family farm and find the ledger does not balance.',
        104,
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        '["Drama"]',
        'PG',
        '["2D"]'
    ),
    (
        '30000000-0000-4000-8000-000000000003',
        'Static Wedding',
        'A sound engineer and a florist discover their venues booked the same hall.',
        96,
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        '["Comedy", "Romance"]',
        'PG-13',
        '["2D", "IMAX"]'
    ) ON CONFLICT (id) DO NOTHING;

-- Showtimes ------------------------------------------------------------------
-- Distinct start times so the ?time= filter is demonstrable: ?time=19:00 returns
-- the 19:30 and 21:00 shows. Each run is an open date range starting today.
INSERT INTO show_times (id, start_time, price, description, price_currency, movie_id, cinema_id, experience_type, start_date, end_date)
VALUES
    (
        '40000000-0000-4000-8000-000000000001',
        '14:00',
        25000,
        'matinee',
        'UGX',
        '30000000-0000-4000-8000-000000000001',
        '20000000-0000-4000-8000-000000000001',
        '2D',
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '30 days'
    ),
    (
        '40000000-0000-4000-8000-000000000002',
        '19:30',
        18000,
        'evening',
        'UGX',
        '30000000-0000-4000-8000-000000000002',
        '20000000-0000-4000-8000-000000000001',
        '2D',
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '30 days'
    ),
    (
        '40000000-0000-4000-8000-000000000003',
        '21:00',
        32000,
        'late show',
        'UGX',
        '30000000-0000-4000-8000-000000000003',
        '20000000-0000-4000-8000-000000000002',
        'IMAX',
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '30 days'
    ) ON CONFLICT (id) DO NOTHING;

-- Existing bookings and one live hold -----------------------------------------
-- Three seats already sold on the first showtime, owned by the non-admin user, so
-- GET /api/show-times/{id} returns a non-zero occupancy and revenue and
-- GET /api/bookings has something in it before you have touched anything.
-- B:3 is a live hold instead of a sale: it shows up in
-- GET /api/show-times/{id}/booked-seats for 10 minutes after the first time the
-- seed runs, then expires like a real hold would. Re-running the seed does not
-- refresh it — ON CONFLICT DO NOTHING leaves reserved_at untouched.
INSERT INTO reservations (id, show_time_id, user_id, seat_no, status, reserved_at)
VALUES
    (
        '50000000-0000-4000-8000-000000000001',
        '40000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000002',
        'A:1',
        'booked',
        NULL
    ),
    (
        '50000000-0000-4000-8000-000000000002',
        '40000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000002',
        'A:2',
        'booked',
        NULL
    ),
    (
        '50000000-0000-4000-8000-000000000003',
        '40000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000002',
        'B:5',
        'booked',
        NULL
    ),
    (
        '50000000-0000-4000-8000-000000000004',
        '40000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000002',
        'B:3',
        'available',
        NOW()
    ) ON CONFLICT (id) DO NOTHING;

-- +goose Down
-- Reverse dependency order, so the foreign keys stay satisfied throughout.
DELETE FROM reservations WHERE id IN (
    '50000000-0000-4000-8000-000000000001',
    '50000000-0000-4000-8000-000000000002',
    '50000000-0000-4000-8000-000000000003',
    '50000000-0000-4000-8000-000000000004'
);
DELETE FROM show_times WHERE id IN (
    '40000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000002',
    '40000000-0000-4000-8000-000000000003'
);
DELETE FROM movies WHERE id IN (
    '30000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000003'
);
DELETE FROM cinemas WHERE id IN (
    '20000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000002'
);
DELETE FROM locations WHERE id = '10000000-0000-4000-8000-000000000001';
DELETE FROM users WHERE id IN (
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000002'
);
