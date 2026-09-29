# Cinehold

**A Go API for holding and booking cinema seats.**

Cinehold is a REST backend for a movie ticket reservation system: users browse what's
playing, hold a seat while they decide, and convert that hold into a booking. Admins
manage the catalogue — movies, locations, cinemas, seat maps and showtimes.

Go 1.27 · PostgreSQL 18+ · stdlib `net/http` · sqlc · goose · no web framework, no ORM

---

## Description

Cinehold is a complete REST backend for a movie ticket reservation system, built to the
[Movie Reservation System](https://roadmap.sh/projects/movie-reservation-system) spec.
Users browse what's playing, hold a seat while they decide, and convert that hold into a
booking; admins manage the catalogue of movies, locations, cinemas, seat maps and
showtimes. All 23 endpoints are implemented.

The part that shaped the design is what happens when two people want the same seat at the
same time.

- **Auth** — short-lived HS256 access tokens (1 hour) paired with long-lived opaque
  refresh tokens (7 days) that live in the database, so they can be revoked server-side.
  Passwords are hashed with Argon2id.
- **Catalogue management** — admins create movies, locations, cinemas and showtimes.
  A cinema's seating layout is stored as JSONB, so an auditorium can have an irregular
  shape without a schema change.
- **Hold, then book** — `POST /api/seats/reserve` puts a 10-minute hold on a seat while
  the user is still deciding. Nothing is sold until `POST /api/seats/book` confirms it.
- **Double-booking protection** — a `UNIQUE (show_time_id, seat_no)` constraint makes it
  structurally impossible for one seat to be held or booked twice, no matter how many API
  instances are running.
- **Abandoned hold recovery** — holds expire after 10 minutes and are reclaimed lazily on
  the next reservation attempt for that seat, so no background sweeper is required.
- **Live seat availability** — a showtime reports the seats that are sold or currently held,
  so a frontend can poll it and grey out the ones nobody can buy. The seat map itself is
  static per cinema, so the UI needs one call for the layout and one cheap call for
  availability.

Every query is authored as SQL in `sql/queries` and compiled into type-safe Go by sqlc,
and the schema is migrated by goose. A malformed query fails at build time instead of in
production. There is no ORM and no reflection-based query builder anywhere in the project.

---

## Motivation

Booking a cinema seat looks simple until you get it right: you cannot hold a row lock for
the ten minutes a user spends deciding, and you cannot let two requests both believe they
own `A:4` — yet shoppers expect a seat to stay theirs while they pick the next one. I spent
seven-plus years building web applications in PHP and Laravel, and recently picked up Go to
get better at it. I'm moving toward systems programming, but I'm starting with the web
because it's what I know — the plan is to get fluent in Go on familiar ground, then keep
going. That meant no framework and no ORM, which Go's standard library supports
comfortably, and a project substantial enough to learn from, which is how I found the
[Movie Reservation System spec](https://roadmap.sh/projects/movie-reservation-system).

I built it to be legible on two levels. As web work, it covers what a production Go service
needs — token auth, admin-only routes, input validation, schema migrations, a clean test
seam, and error contracts shaped like Laravel's, so a UI can bind failures straight to form
fields — and none of it comes from a framework, so the mechanics stay visible. As systems
work, the substance sits underneath: concurrency correctness enforced by the schema rather
than by trust, queries compiled ahead of time so a broken one cannot reach production,
aggregates assembled in SQL to avoid N+1 round trips. And nothing assumes a single process —
a seat cannot be double-booked even with several instances behind a load balancer.

---

## Quick Start

### Prerequisites

- **Go 1.27+**
- **PostgreSQL 18+** — every primary key is generated with the built-in `uuidv7()`
  function, which landed in PostgreSQL 18
- **`sqlc`** — only needed if you change anything under `sql/`
- **`goose`** — only needed to run migrations and the seed

### 1. Get the code and configure it

```bash
git clone https://github.com/geneowak/cinehold.git
cd cinehold

cp .env.example .env
```

Then fill in `.env`:

```ini
DB_URL="postgres://postgres:postgres@localhost:5432/cinehold?sslmode=disable"
PLATFORM="dev"
JWT_SECRET="<paste a long random string here>"
PORT="8080"
```

Generate a secret with:

```bash
openssl rand -base64 64
```

| Variable | Required | Notes |
| --- | --- | --- |
| `DB_URL` | yes | pgx connection string. The server exits immediately if it's missing. |
| `PLATFORM` | yes | Required by the config, though it isn't read anywhere yet. |
| `JWT_SECRET` | yes | HS256 signing key for access tokens. |
| `PORT` | no | Defaults to `8080`. |
| `TEST_DB_URL` | tests only | See [Contributing](#contributing). |

### 2. Create the database

```bash
createdb cinehold
```

### 3. Run the migrations

Migrations are plain [goose](https://github.com/pressly/goose) files in `sql/schema` and
are also embedded into the binary, so the goose CLI is enough:

```bash
goose -dir sql/schema postgres "$DB_URL" up
```

### 4. Seed the database

Migrations give you an empty schema. To get a browsable catalogue and two working
accounts, apply the seed:

```bash
goose -dir sql/schema/seed -no-versioning postgres "$DB_URL" up
```

The `-no-versioning` flag is what makes this safe to run alongside the numbered
migrations. Without it goose would record the seed in the same `goose_db_version`
table and its version numbers would collide with `sql/schema`, permanently marking
it as applied. With it, the statements are applied in file order and nothing is
recorded, so **the seed is safe to re-run at any time** — every row uses a fixed
id and `ON CONFLICT DO NOTHING`, so a second run is a no-op rather than a
duplicate key error.

It creates two throwaway accounts, one location, two cinemas, three movies,
three showtimes and three existing bookings:

| Email | Password | Admin |
| --- | --- | --- |
| `admin@cinehold.test` | `password123` | yes |
| `user@cinehold.test` | `password123` | no |

These credentials are committed on purpose so a reviewer can get in without
running SQL. Don't deploy them anywhere.

### 5. Run it

```bash
go run .
# Listening on port: 8080
```

### 6. Book a seat

With the seed applied, the whole product is reachable in four calls. Log in as the
seeded admin and pull a token out of the response:

```bash
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@cinehold.test","password":"password123"}'
```

```bash
# what's showing — the optional filters are genre, time and date
curl "http://localhost:8080/api/movies" -H "Authorization: Bearer $TOKEN"
curl "http://localhost:8080/api/movies?genre=Action" -H "Authorization: Bearer $TOKEN"
curl "http://localhost:8080/api/movies?time=19:00" -H "Authorization: Bearer $TOKEN"
```

Grab a `show_times` id out of that response. Check what a client would see when choosing a
seat, then hold one and convert the hold into a booking:

```bash
# the seat map, plus the seats nobody can currently select
curl http://localhost:8080/api/show-times/<show-time-id> \
  -H "Authorization: Bearer $TOKEN"
curl http://localhost:8080/api/show-times/<show-time-id>/booked-seats \
  -H "Authorization: Bearer $TOKEN"
# ["A:1","A:2","B:5"]

# hold a seat for 10 minutes, returns a reservation id
curl -X POST http://localhost:8080/api/seats/reserve \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"seat":"C:1","show_time_id":"<show-time-id>"}'

# buy one or more holds in a single call
curl -X POST http://localhost:8080/api/seats/book \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"seat_reservations":["<reservation-id>"]}'
```

Log in as `user@cinehold.test` instead and the showtime detail call drops the three
analytics fields, since those are admin-only.

> The `genre` filter matches JSON array elements exactly, so it is **case
> sensitive** — `?genre=Action` returns results, `?genre=action` returns nothing.
>
> A filter that matches no rows responds `200` with a `null` body rather than an
> empty array. See [Things to fix](#things-to-fix).

Prefer to start from scratch? Sign up your own account instead, then promote it the
way the seed did — set `is_admin = true` for your user directly in the database.
The admin routes require an existing admin, so there has to be a first one.

---

## Usage

All routes are registered in a single place, [`handlers/handlers.go`](handlers/handlers.go).
Every route is namespaced under `/api` and the four auth routes under `/api/auth`.

### Public

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/api/auth/signup` | Create an account. Rejects emails that are already registered. |
| `POST` | `/api/auth/login` | Exchange email + password for an access token and a refresh token. |
| `POST` | `/api/auth/refresh` | Exchange a refresh token (Bearer) for a fresh access token. |
| `POST` | `/api/auth/revoke` | Revoke the refresh token supplied in the Bearer header. `204`. |

### Admin

Requires an access token belonging to a user with `is_admin = true`.

| Method | Path | Description |
| --- | --- | --- |
| `PUT` | `/api/users/{userId}` | Grant or revoke admin (`{"is_admin": true}`). An admin cannot change their own status, so the system always keeps at least one. |
| `POST` | `/api/movies` | Create a movie. |
| `POST` | `/api/movies/{movieId}/show-times` | Schedule a movie at a cinema over a date range. |
| `GET` | `/api/admin/movies` | Every movie with its showtimes, for management. |
| `PUT` | `/api/movies/{movieId}` | Update movie details. Rejected while the movie has ongoing showtimes. |
| `DELETE` | `/api/movies/{movieId}` | Delete a movie. Rejected while the movie has ongoing showtimes. |
| `POST` | `/api/locations` | Create a location. |
| `GET` | `/api/locations` | List all locations. |
| `GET` | `/api/locations/{locationId}` | One location with its cinemas. |
| `POST` | `/api/cinemas` | Create a cinema with its seat map. |
| `PUT` | `/api/cinemas/{cinemaId}` | Update a cinema, including its seat map. Rejected while the cinema has ongoing showtimes, since that would invalidate seats people already paid for. |

### Authenticated user

Requires any valid access token.

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/movies` | Movies currently showing, with their showtimes. Optional filters: `?genre=`, `?time=15:04`, `?date=2006-01-02`. |
| `GET` | `/api/movies/{movieId}` | One movie with its showtimes. |
| `GET` | `/api/show-times/{showTimeId}` | One showtime with its cinema and seat map. Admins additionally get capacity, bookings and revenue — see [Showtime detail](#showtime-detail). |
| `GET` | `/api/show-times/{showTimeId}/booked-seats` | The seats nobody can select right now — sold, or held within the last 10 minutes. A bare array of seat numbers, meant to be polled. |
| `POST` | `/api/seats/reserve` | Hold a seat for 10 minutes. `201` with the reservation. |
| `POST` | `/api/seats/book` | Confirm previously held seats. |
| `GET` | `/api/bookings` | The current user's confirmed bookings. |
| `DELETE` | `/api/bookings/{reservationId}` | Cancel one of the current user's bookings. `204`. |

### Authentication

Login returns both tokens. Both are sent in the `Authorization: Bearer <token>` header —
the access token on ordinary requests, the refresh token on `/api/auth/refresh` and
`/api/auth/revoke`.

```jsonc
{
  "id": "0192...",
  "email": "you@example.com",
  "is_admin": false,
  "token": "eyJhbGciOiJIUzI1NiIs...",        // HS256 JWT, expires in 1 hour
  "refresh_token": "3f9a1c..."               // opaque, stored server-side, expires in 7 days
}
```

```bash
curl -X POST http://localhost:8080/api/auth/refresh \
  -H "Authorization: Bearer $REFRESH_TOKEN"
# {"token":"eyJhbGciOiJIUzI1NiIs..."}
```

When an access token expires, trade the refresh token for a new one. Refreshing does not
rotate the refresh token, and once a token has been revoked it is rejected on every
subsequent refresh.

### Showtime detail

`GET /api/show-times/{showTimeId}` is the one endpoint whose response depends on who is
asking. Everyone gets the showtime and the cinema it plays in, including the full seat map,
because a user needs the layout to pick a seat. Admins get three extra fields describing
how that screening is selling.

```jsonc
// any signed-in user
{
  "id": "0192...",
  "start_time": "2000-01-01T14:00:00Z",   // see the note below
  "price": 25000,
  "description": "matinee",
  "price_currency": "UGX",
  "movie_id": "0192...",
  "cinema_id": "0192...",
  "experience_type": "2D",
  "start_date": "2026-09-27T00:00:00Z",
  "end_date": "2026-10-27T00:00:00Z",
  "created_at": "2026-09-27T09:17:27Z",
  "updated_at": "2026-09-27T09:17:27Z",
  "cinema": {
    "id": "0192...",
    "location_id": "0192...",
    "name": "Screen 1",
    "experience_types": ["2D", "3D"],
    "seat_map": { "rows": [ /* ... */ ], "total_seats": 24, "screen": "center" }
  }

  // admins additionally get:
  // "cinema_capacity": 24,
  // "current_bookings": 3,
  // "current_revenue": 75000
}
```

`start_time` comes back as a full timestamp with a year of `2000` because the column is
Postgres `time`, which has no date, and pgx scans it into a `time.Time`. The `14:00` in
the example is the part that matters; the rest is an artefact of the round trip.

The revenue figure is gross and assumes every booking is a completed sale — it counts
`booked` rows and multiplies by the showtime price, so it ignores refunds, which don't
exist yet.

### Checking which seats are gone

`GET /api/show-times/{showTimeId}/booked-seats` exists so a frontend can grey out seats
while someone is picking. It's a separate call from the showtime detail above because the
seat map is static per cinema and this part changes constantly — poll it, don't refetch
the layout.

```bash
curl http://localhost:8080/api/show-times/$SHOW_TIME_ID/booked-seats \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

```jsonc
["A:1", "A:2", "B:5"]   // a bare array of seat numbers
```

A seat appears in that list if it is sold, or if someone is holding it and the hold is
younger than 10 minutes. A hold that has just lapsed disappears from the list, because
it's free again — the next person to reserve it takes it.

That makes the endpoint and `POST /api/seats/reserve` agree exactly: anything this
endpoint lists, the reserve call will reject. Both sides measure the 10 minutes from
`reserved_at` with the same strict comparison, so they don't disagree at the boundary
either.

> A showtime with nothing reserved responds `200` with a `null` body rather than an empty
> array, so a polling client needs a null check on every tick. See
> [Things to fix](#things-to-fix).

### The seat flow

This is the core of the API. A seat is *held* while the user decides, then *booked* once
they commit.

Before any of it, a client fetches `GET /api/show-times/{showTimeId}` for the seat map and
then polls `GET /api/show-times/{showTimeId}/booked-seats` to grey out anything taken —
both covered in [Showtime detail](#showtime-detail) and
[Checking which seats are gone](#checking-which-seats-are-gone). What follows is the
part that writes.

**1. Hold a seat.** The response is the reservation you'll need to book it.

```bash
curl -X POST http://localhost:8080/api/seats/reserve \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"show_time_id":"0192...","seat":"A:4"}'
```

```jsonc
{
  "id": "0192...",              // use this to book the seat
  "show_time_id": "0192...",
  "user_id": "0192...",
  "seat_no": "A:4",
  "status": "available",        // a hold, not yet sold
  "reserved_at": "2026-09-26T12:04:11Z",
  "created_at": "2026-09-26T12:04:11Z",
  "updated_at": "2026-09-26T12:04:11Z"
}
```

The request fails with `422` if the seat doesn't exist in that cinema's seat map, has
already been booked, or is currently held by someone else.

**2. Hold the rest.** Repeat for each seat in the row. The reservation `id` is what you
carry forward, not the seat number.

**3. Book them.** Pass every reservation id at once.

```bash
curl -X POST http://localhost:8080/api/seats/book \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"seat_reservations":["0192...","0192..."]}'
```

Only reservations that belong to the caller and are still `available` are accepted. On
success each row comes back with `status: "booked"` and a null `reserved_at`.

The call is **all or nothing**. The seats are confirmed inside a single transaction, so
if any one of them turns out to be unavailable — someone else booked it between the check
and the write, or the same id appears twice in one request — nothing is booked, and the
whole batch comes back `422` naming every seat that failed:

```json
{
  "message": "There were some validation errors",
  "errors": { "seat_reservations[1]": ["Seat Reservation not found."] }
}
```

You never end up with a partial booking to unpick.

**4. Review or cancel.**

```bash
curl http://localhost:8080/api/bookings -H "Authorization: Bearer $ACCESS_TOKEN"
curl -X DELETE http://localhost:8080/api/bookings/$RESERVATION_ID -H "Authorization: Bearer $ACCESS_TOKEN"
```

**How long a hold lasts:** 10 minutes, counted from `reserved_at`. There is no background
job expiring them — if a hold is stale, the next person to request that seat takes it, and
the original hold is reassigned. A hold is not a booking until step 3 succeeds. That same
10 minutes is what the availability endpoint reports on, so a lapsed hold shows up as
selectable again in the UI before anyone has to claim it.

### Seat maps

A cinema's layout is a JSONB document, which keeps irregular auditoriums out of the
relational schema. `total_seats` is denormalised into the document so capacity and revenue
can be computed without counting rows.

```jsonc
{
  "rows": [
    {
      "row": "A",
      "seats": [
        { "number": 1, "type": "regular" },
        { "number": 2, "type": "regular" }
      ]
    },
    { "row": "B", "seats": [ { "number": 1, "type": "vip" } ] }
  ],
  "total_seats": 3,
  "screen": "center"
}
```

Seats are addressed as `"{row}:{number}"`, so `A:4` above is row `A`, seat `4`. The
per-seat `type` is stored but never read — see
[Deliberately out of scope](#deliberately-out-of-scope).

### Creating a cinema

```bash
curl -X POST http://localhost:8080/api/cinemas \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Screen 4",
    "location_id": "0192...",
    "experience_types": ["2D", "3D"],
    "seat_map": { "rows": [...], "total_seats": 3, "screen": "center" }
  }'
```

### Scheduling a showtime

```bash
curl -X POST http://localhost:8080/api/movies/$MOVIE_ID/show-times \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "start_time": "19:30",
    "price": 25000,
    "description": "opening night",
    "price_currency": "UGX",
    "cinema_id": "0192...",
    "experience_type": "2D",
    "start_date": "2026-09-26",
    "end_date": "2026-10-26"
  }'
```

A showtime is a **date range**, not an instant: a movie playing at a cinema from one date
to another, at one price, in one experience type. That's a simplification — see
[Deliberately out of scope](#deliberately-out-of-scope).

### Error responses

Two shapes. Simple failures:

```json
{ "error": "Show time not found" }
```

Validation failures return `422` with a field-keyed map, so a client can highlight the
offending inputs:

```json
{
  "message": "There were some validation errors",
  "errors": {
    "email": ["The email must be a valid email."],
    "seat_reservations[0]": ["Seat Reservation not found."]
  }
}
```

---

## Architecture

### Layout

```
main.go               entrypoint: config, DB pool, server
handlers/             HTTP layer — routing, middleware, validation, JSON
  handlers.go         every route in the project, in one file
  config.go           ApiConfig: the single dependency-injection point
  middlewareAuth.go   requires a valid access token
  middlewareAdminAuth.go  requires a valid access token and is_admin
  json.go             response and error helpers
  validation.go       validator setup, error message translation
  dbValidatorFuncs.go custom validators that hit the database
  handle*.go          one file per route
internal/
  auth/               JWT creation/validation, password hashing, header parsing
  hashing/            vendored Argon2id primitives
  types/              custom sqlc column types (SeatMap, StringSlice)
  database/           repository layer — entirely sqlc-generated
  testdb/             test database helpers
sql/
  schema/             goose migrations
    seed/             development seed data, applied with goose -no-versioning
  queries/            sqlc queries, with -- name: QueryName :one/:many/:exec
  embed.go            embeds schema/*.sql into the binary
```

Dependencies point one way: `handlers` → `internal/*` → `internal/database`. Nothing in
`internal/` knows HTTP exists.

### Dependency Injection

There is no DI framework. `ApiConfig` carries a `database.Querier` **interface** rather
than a concrete `*database.Queries`, so tests can substitute either a transaction-bound
querier or a mock:

```go
type ApiConfig struct {
    DB        database.Querier
    Pool      TxBeginner
    Platform  string
    JwtSecret string
    Validate  *validator.Validate
}
```

`DB` answers queries; `Pool` opens transactions. They're separate fields because
`Querier` is generated by sqlc from the files in `sql/queries` and therefore has no
`Begin` in it — and a transaction can't be faked by implementing a query interface.
`TxBeginner` is a one-method interface, `Begin(ctx) (pgx.Tx, error)`, satisfied by both
`*pgxpool.Pool` and `*pgx.Conn`, so the production path passes the pool and tests pass a
connection:

```go
cfg := handlers.ApiConfig{
    DB:   database.New(db),   // queries
    Pool: db,                 // transactions
    // ...
}
```

A handler that needs atomicity takes a transaction off `Pool` and binds a fresh querier to
it. `*pgx.Tx` satisfies the same `database.DBTX` the generated code uses, so
`database.New(tx)` returns a `Querier` scoped to that transaction — no second interface
needed. See [`handlers/handleSeatBooking.go`](handlers/handleSeatBooking.go) and
[`handlers/testHelpers_test.go`](handlers/testHelpers_test.go).

### Schema

| Table | Purpose |
| --- | --- |
| `users` | Accounts. Admin is a single `is_admin` boolean — no roles table. |
| `refresh_tokens` | Server-side session store. The token itself is the primary key; `revoked_at` is what makes revocation enforceable. |
| `movies` | Film catalogue. `genre` and `experience_types` are JSON arrays. |
| `locations` | Physical venues, e.g. a mall. |
| `cinemas` | An auditorium within a location, with its own JSONB `seat_map`. |
| `show_times` | A movie playing at a cinema across a date range. |
| `reservations` | One row per seat: the hold, and then the booking. |

Every primary key except `refresh_tokens.token` is `uuidv7()`, generated in SQL rather than
the application, which keeps them time-sortable and therefore index-friendly.

### How the seat model works

`reservations.status` is the whole state machine:

- `available` — a live hold, with `reserved_at` set. It belongs to a user but nobody has
  paid for it.
- `booked` — sold. `reserved_at` is nulled out on confirmation.

```sql
CONSTRAINT unx_show_time_seat_no UNIQUE (show_time_id, seat_no)
```

That constraint is the real guarantee. Because a seat can only have one row per showtime,
two concurrent requests for `A:4` cannot both succeed — one gets a unique violation, no
matter how the application code is written. The handler checks first for a friendlier
error message; the constraint is what makes the check trustworthy.

Booking a hold is a different operation from creating one, so it gets a different
protection. `POST /api/seats/book` runs inside a transaction, and its `UPDATE` carries
`AND status = 'available'`, which makes it a compare-and-set: a row can only move from
`available` to `booked`, never from `booked` to `booked` again. Under Postgres' default
`READ COMMITTED` isolation the predicate is re-checked after the row lock is taken, so
if a competing request committed first this one matches nothing, gets `pgx.ErrNoRows`,
and rolls the whole batch back. That's what makes the handler's up-front check a
convenience rather than the only thing standing between two users and the same seat.

Expired holds are reclaimed lazily rather than swept. `POST /api/seats/reserve` reads the
existing row, and if `status = 'available'` but `reserved_at` is more than 10 minutes old,
it reassigns the row to the new user instead of failing. There's no cron job and no
per-seat timer.

The same 10-minute rule is what `GET /api/show-times/{showTimeId}/booked-seats` reports on,
which means the 10 minutes is enforced in two places that have to agree: the reserve
handler decides whether a seat can be taken, and the availability query decides whether the
UI is allowed to offer it. Both measure from `reserved_at` and both use a strict
comparison, so a seat is never simultaneously offered and rejected at the boundary. If one
side is ever loosened, the other has to move with it.

### Domain invariants

Two rules are enforced in the handlers because the database can't express them:

- A movie with ongoing showtimes cannot be edited or deleted, so details people already
  booked against don't change underneath them.
- A cinema with ongoing showtimes cannot be updated, because changing a seat map would
  invalidate seats that have already been sold.

And one in the schema: `ON DELETE CASCADE` from `show_times`, `locations` and `users` means
deleting a movie, cinema, location or user cleans up the dependent rows for you.

### Where the JSONB is

Nested aggregates are built in SQL with `jsonb_agg` inside `LEFT JOIN LATERAL` rather than
fetched with follow-up queries, which keeps movie + showtime and location + cinema reads
to a single round trip. `json.RawMessage` fields appear in a couple of handlers to stop
sqlc from base64-encoding nested JSON columns on its way through the generated structs.

### Laravel conventions, deliberately carried over

Seven years in Laravel leaves fingerprints. Three of its conventions turned out to be worth
reproducing in Go, and all three are implemented by hand here rather than pulled from a
framework.

**Error responses.** Validation failures return `422` with a field-keyed error map, the
shape every Laravel frontend developer already expects:

```json
{
  "message": "There were some validation errors",
  "errors": { "email": ["The email must be a valid email."] }
}
```

`go-playground/validator` reports failures by struct tag, which a JavaScript client can't
do anything useful with. [`handlers/validation.go`](handlers/validation.go) translates on
two fronts: `RegisterTagNameFunc` maps field names to their JSON equivalents so error keys
match the wire format rather than the Go struct, and `getErrorMsg` hand-writes a readable
message per validation tag — including separate wording for slices and maps versus plain
strings, so a "must contain at least 1 item" never reads as a character count. The payoff
is that a UI can bind straight to form inputs.

**Column casting.** Eloquent hands back JSON columns as collections and objects rather than
strings. `internal/types` does the same job for sqlc: `SeatMap` and `StringSlice` implement
`driver.Valuer` and `sql.Scanner`, and the `overrides` in [`sqlc.yaml`](sqlc.yaml) point
`cinemas.seat_map`, `movies.genre` and the `experience_types` columns at them. A cinema's
seating layout therefore arrives as a typed Go struct instead of a `[]byte` that every
caller has to unmarshal and type-assert.

**Test isolation.** [`internal/testdb`](internal/testdb/testdb.go) wraps each test in a
transaction and rolls it back on completion, the same idea as Laravel's `RefreshDatabase`
trait — every case starts from a clean slate without truncating tables between runs.
Handlers that open their own transaction are supported too: `Scope.Beginner` hands out a
savepoint-backed pseudo-nested transaction, so a test can drive a transactional handler
and still assert against the outer transaction afterwards.

---

## Retrospective & Future Work

### Things to fix

- [ ] The `genre` filter should be case insensitive. It matches JSON array elements with `@>`, so `?genre=Action` matches and `?genre=action` silently returns nothing
- [ ] List endpoints should return `[]` rather than `null` when a filter matches no rows. `respondWithJSON` marshals a nil slice to `null`, so a client that does `data.map(...)` on an empty result throws. It bites hardest on `GET /api/show-times/{showTimeId}/booked-seats`, which a frontend is meant to poll every few seconds and has to null-check every time
- [ ] Rename the `reservations` table to `bookings`, with `status` values of `pending` and `booked`. The structure can stay as it is, but `bookings` is the more intuitive name — right now routes say `/api/bookings` while the table behind them is called `reservations`, which is needlessly confusing
- [ ] Change every `timestamp` column to `timestamptz` in UTC. This would have prevented the time-zone bug I hit while calculating how long a seat had been reserved; I patched it in `7a47fd6` by converting the `reservations` table, but that migration shouldn't have been necessary
- [ ] Add pagination. No query uses `LIMIT`/`OFFSET`, so `GET /api/movies`, `GET /api/locations` and `GET /api/bookings` all return unbounded result sets

### Deliberately out of scope

- [ ] Payment processing or ticketing provider integration
- [ ] Email or SMS notifications, including booking confirmations and showtime reminders
- [ ] A frontend, or any static file serving — `SetupServer` takes a `filePathRoot` that it currently ignores
- [ ] Seat map editing UI. The layout is uploaded as a single JSONB document rather than drawn in a browser
- [ ] Seat classes and per-seat pricing. The per-seat `type` field is stored but never read, so it can't affect price
- [ ] A background sweeper for expired holds. The lazy reclaim on the next reserve attempt covers the same ground
- [ ] Per-instant showtimes. A showtime is a date range at a single price, so a cinema can't run different prices for a morning and an evening screening of the same film
- [ ] Showtime overlap detection. Nothing currently stops two showtimes from being scheduled in the same cinema at the same time. This is deliberately out of scope because the logic is substantial, but it's worth recording the approach I'd take. When creating a showtime, validate that the cinema is available at the proposed time — this can be done by checking whether any existing booking runs beyond it. Here's a brief proposal:

    1. Add a cleanup time to the cinema table and make it required for each cinema. This field indicates how long it takes the staff to clean up the cinema and have it ready for the next movie. It should also factor in the time it takes the people to exit the cinema.
    2. When looking for existing bookings (which could be a separate table or calculated on the fly), add this time to the movie length to determine when the cinema will next be available for another movie.
    3. The same check can back an API which the UI uses to display the available cinemas when the user selects a time slot.

- [ ] Movie poster uploads. `movies.poster_image_url` exists in the schema but no endpoint sets it
- [ ] Refresh token rotation, and reuse detection
- [ ] Roles and permissions beyond the single `is_admin` boolean
- [ ] Audit logging of admin actions
- [ ] Observability: no structured logging, metrics, tracing or request IDs
- [ ] Rate limiting, CORS, panic recovery, and graceful shutdown
- [ ] Docker, docker-compose, a Makefile, and CI
- [ ] A linter configuration
- [ ] Wider test coverage. Only `handleCreateMovie` and the booking transaction in `handleSeatBooking` have handler tests; the seat reserve flow, and the rest of the write paths, have none
- [ ] Production password hashing parameters. `hashing.ProdParams` is defined and unused; the defaults are still in use

---

## Contributing

Contributions are welcome — issues, bug reports, and pull requests.

### Running the tests

```bash
cp .env.testing.example .env.testing   # required
```

Then set `TEST_DB_URL` in `.env.testing` to a **separate, throwaway** database. The test
helpers run the real migrations and wrap every test in a transaction that is rolled back
when the test finishes, so a test can never leave data behind — but pointing this at a
database you care about is still a bad idea.

```bash
go test ./...
```

Two things to know:

- If `TEST_DB_URL` is empty, tests that need a database skip themselves rather than fail.
  If the `.env.testing` file is *missing*, they fail outright.
- The path to `.env.testing` is relative (`../.env.testing`), so it resolves against the
  package directory of whichever test calls the helper. The only caller today lives in
  `handlers/`, which puts it at the repo root.
- The test database has to actually match the migration files. `goose_db_version` records
  which migrations it thinks ran, so if you edit a migration that has already been
  applied, goose still skips it and every database-backed test fails on a missing column
  rather than anything to do with your change. Drop and recreate the test database to
  resync.

### The development loop

Start from a clean database whenever you want the seeded state back, since nothing
in the app resets it for you:

```bash
dropdb cinehold && createdb cinehold
goose -dir sql/schema postgres "$DB_URL" up
goose -dir sql/schema/seed -no-versioning postgres "$DB_URL" up
```

The seed is idempotent, so re-running just the last line is usually enough, and
rolling it back by hand is a single `goose -dir sql/schema/seed -no-versioning
postgres "$DB_URL" down`.

The database layer is generated, so SQL changes have two steps:

```bash
# 1. edit sql/queries/*.sql (and add a migration in sql/schema/ if the schema changed)
# 2. regenerate the typed Go
sqlc generate

# 3. rebuild and test
go build ./... && go test ./...
```

Everything in `internal/database/` is generated by sqlc and carries a
`Code generated by sqlc. DO NOT EDIT.` header. **Never edit it by hand** — change the SQL
and regenerate.

### Conventions

- **One route, one file.** `handleSeatBooking.go` contains `handleSeatBooking`, and nothing
  else does. Add new routes the same way.
- **One request struct per handler**, declared unexported at the top of the file, with
  `validate` tags. Tag names are translated to their JSON equivalents, so validation error
  keys match the wire format rather than the Go field names.
- **Migrations need both directions.** Every file in `sql/schema/` should have a
  `-- +goose Up` and a `-- +goose Down` section.
- **Business logic lives in the handler.** There is deliberately no service layer; handlers
  decode, validate, call a query, and respond. Keep it that way unless you're introducing a
  layer for a specific reason.
- **Let the database enforce invariants** where it can, and check in the handler only to
  return a friendlier error.
- **Never commit `.env` or `.env.testing`.** Both are gitignored. `.env.example` and
  `.env.testing.example` are committed and should stay key-complete and value-free.

### Known gaps in the tooling

There's no CI pipeline and no linter config committed yet, so run `go vet ./...` and
`gofmt -l .` locally before opening a pull request.

---

## License

[MIT](LICENSE) — free to use, modify and ship, including commercially.
