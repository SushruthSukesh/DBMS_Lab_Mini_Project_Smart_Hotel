# Smart Hotel Management System

## Project title

**SmartStay: A Data-Driven Hotel Reservation and Guest Experience Platform**

SmartStay manages room inventory, guest reservations, payments, availability, and
guest preferences. It goes beyond basic CRUD by preventing double bookings,
calculating reservation totals transactionally, auditing status changes, and
supporting preference-based recommendations.

## Requirements coverage

| Requirement | Implementation |
|---|---|
| SQL database | MySQL 8.0 schema in [`smart_hotel_management.sql`](./smart_hotel_management.sql) |
| Second database paradigm | MongoDB document model in [`mongo_guest_preferences.json`](./mongo_guest_preferences.json) |
| ER design | Entities and relationships documented below |
| DDL and constraints | Tables, keys, foreign keys, `CHECK`, `UNIQUE`, `ENUM` |
| DML | Seed inserts, update, select, aggregate queries, and delete example |
| Advanced SQL | Transaction, view, stored procedure, triggers, indexes, and full-text search |
| Authentication | `Hotel_User` with Admin, Receptionist, and Manager roles |
| Web application | Next.js frontend with Route Handlers/API layer recommended |

## Objectives and functional requirements

1. Register guests and maintain verified contact and identity information.
2. Maintain room types, rates, capacity, amenities, and room status.
3. Search available rooms by date, capacity, type, and amenities.
4. Create, confirm, check in, check out, and cancel reservations.
5. Accept and reconcile payments against reservations.
6. Prevent overlapping reservations and capacity violations at database level.
7. Provide dashboards for occupancy, revenue, unpaid balances, and upcoming arrivals.
8. Store flexible guest preferences and feedback in MongoDB for recommendations.
9. Restrict administrative operations using role-based authentication.

## Architecture and database justification

The application uses a layered architecture:

`Next.js UI -> Route Handlers/API -> Service layer -> MySQL + MongoDB`

MySQL is appropriate for reservations and payments because foreign keys,
transactions, constraints, and consistent totals are essential. MongoDB is
appropriate for guest preferences and feedback because these fields are
optional, nested, and expected to evolve without changing the reservation
schema. The API reads database credentials from environment variables such as
`MYSQL_URL` and `MONGODB_URI`; secrets must never be committed.

## Relational schema

- **Guest**(`guest_id` PK, first_name, last_name, email, phone, address,
  date_of_birth, id_proof)
- **Room_Type**(`room_type_id` PK, type_name, description, price_per_night,
  capacity, amenities)
- **Room**(`room_id` PK, room_number, `room_type_id` FK, floor, status)
- **Reservation**(`reservation_id` PK, `guest_id` FK, `room_id` FK, check_in,
  check_out, guests_count, booking_status, total_amount)
- **Payment**(`payment_id` PK, `reservation_id` FK, amount, payment_date,
  payment_method, payment_status, transaction_id)
- **Hotel_User**(`user_id` PK, full_name, email, password_hash, role, is_active)
- **Reservation_Audit**(`audit_id` PK, `reservation_id` FK, action_name,
  old_status, new_status, changed_at)

Relationships: one guest can have many reservations; one room can have many
non-overlapping reservations; one room type can contain many rooms; one
reservation can have many payments and audit records.

## MongoDB model and retrieval strategy

The `guest_preferences` collection stores one document per guest. Its nested
preference and stay-history fields are embedded because they are read together
with the guest profile. Create indexes on `guestId` and
`preferences.amenities`; use a text index on `searchableText` for keyword
recommendations. A MongoDB aggregation can match a requested amenity, unwind
stay history, and sort by rating and recency. The SQL reservation result is
always checked before a recommendation is offered.

## Advanced feature highlights

- `sp_create_reservation` calculates the total and commits it atomically.
- `trg_reservation_validate` rejects invalid dates, capacity violations, and
  overlapping active reservations.
- `trg_reservation_audit` records booking-status changes.
- `v_active_reservations` exposes a dashboard-ready balance calculation.
- Composite indexes accelerate availability and guest-history queries.
- Full-text search supports amenity-based room discovery.

## Next.js implementation

The included Next.js application provides a responsive operations dashboard,
reservations table, room inventory, quick actions, and a reservation modal.
The API routes are:

- `GET /api/dashboard`: reads the dashboard view, room inventory, occupancy,
  arrivals, departures, revenue, and outstanding balances from MySQL.
- `POST /api/reservations`: validates the request and calls
  `sp_create_reservation`, preserving the database's transaction and
  double-booking protections.

Run `npm install`, copy `.env.example` to `.env.local`, configure the MySQL and
MongoDB URLs, then run `npm run dev`. Database credentials remain server-side.
The `Hotel_User` table is ready for the authentication layer; production
deployment should add an HTTP-only session cookie, Argon2/bcrypt password
verification, and role checks in each protected route.

## Setup

1. Install MySQL 8.0+ and MongoDB.
2. Run `smart_hotel_management.sql` in MySQL Workbench or the MySQL CLI.
3. Create a MongoDB database named `smart_hotel_management` and insert the
   sample document into `guest_preferences`.
4. Configure `MYSQL_URL`, `MONGODB_URI`, and an application session secret in
   the Next.js environment.
5. Run the Next.js application with `npm install` followed by `npm run dev`.

## Testing checklist

- Attempt an overlapping reservation: the validation trigger must reject it.
- Attempt a reservation above room capacity: the trigger must reject it.
- Create a valid reservation and payment: the view must show zero balance.
- Change a booking status: `Reservation_Audit` must receive a record.
- Search for Wi-Fi and breakfast: the full-text query must return matching types.
- Verify receptionist and manager permissions through the API.
- Verify that invalid email, dates, negative rates, and zero guests are rejected.
