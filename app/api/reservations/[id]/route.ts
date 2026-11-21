
import { NextResponse } from "next/server";
import { getMySQL } from "@/lib/db";

type RouteContext = { params: { id: string } };

function parseReservationId(value: string) {
  const reservationId = Number(value);
  return Number.isInteger(reservationId) && reservationId > 0
    ? reservationId
    : null;
}

function getErrorMessage(error: unknown) {
  if (error instanceof AggregateError) {
    const firstError = error.errors[0];

    if (
      firstError &&
      typeof firstError === "object" &&
      "code" in firstError &&
      firstError.code === "ECONNREFUSED"
    ) {
      return "MySQL is not running or is not reachable at MYSQL_URL.";
    }
  }

  return error instanceof Error && error.message
    ? error.message
    : "Reservation operation failed.";
}

export async function PATCH(request: Request, { params }: RouteContext) {
  const reservationId = parseReservationId(params.id);

  if (!reservationId) {
    return NextResponse.json(
      { error: "Invalid reservation ID." },
      { status: 400 }
    );
  }

  try {
    const body = await request.json() as Record<string, string>;

    const guestId = Number(body.guestId);
    const roomId = Number(body.roomId);
    const guestsCount = Number(body.guestsCount);

    const checkIn = new Date(`${body.checkIn}T00:00:00`);
    const checkOut = new Date(`${body.checkOut}T00:00:00`);

    if (
      !Number.isInteger(guestId) || guestId < 1 ||
      !Number.isInteger(roomId) || roomId < 1 ||
      !body.checkIn ||
      !body.checkOut ||
      !Number.isInteger(guestsCount) ||
      guestsCount < 1 ||
      Number.isNaN(checkIn.valueOf()) ||
      Number.isNaN(checkOut.valueOf()) ||
      checkOut <= checkIn
    ) {
      return NextResponse.json(
        { error: "Provide valid guest, room, dates, and guest count." },
        { status: 400 }
      );
    }

    await getMySQL().query(
      "CALL sp_update_reservation(?, ?, ?, ?, ?, ?)",
      [
        reservationId,
        guestId,
        roomId,
        body.checkIn,
        body.checkOut,
        guestsCount
      ]
    );

    return NextResponse.json({ reservationId });
  } catch (error) {
    console.error("Reservation update failed", error);

    return NextResponse.json(
      { error: getErrorMessage(error) },
      { status: 400 }
    );
  }
}

export async function DELETE(_request: Request, { params }: RouteContext) {
  const reservationId = parseReservationId(params.id);

  if (!reservationId) {
    return NextResponse.json(
      { error: "Invalid reservation ID." },
      { status: 400 }
    );
  }

  try {
    await getMySQL().query(
      "CALL sp_delete_reservation(?)",
      [reservationId]
    );

    return NextResponse.json({ reservationId });
  } catch (error) {
    console.error("Reservation deletion failed", error);

    return NextResponse.json(
      { error: getErrorMessage(error) },
      { status: 400 }
    );
  }
}
