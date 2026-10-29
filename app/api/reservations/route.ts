import { NextResponse } from "next/server";
import { getMySQL } from "@/lib/db";
import { RowDataPacket } from "mysql2";

function getErrorMessage(error: unknown) {
  if (error instanceof AggregateError) {
    const firstError = error.errors[0];
    if (firstError && typeof firstError === "object" && "code" in firstError && firstError.code === "ECONNREFUSED") {
      return "MySQL is not running or is not reachable at MYSQL_URL. Start MySQL and try again.";
    }
  }
  return error instanceof Error && error.message
    ? error.message
    : "Reservation could not be created.";
}

export async function POST(request: Request) {
  try {
    const body = await request.json() as Record<string, string>;
    const guestId = Number(body.guestId);
    const roomId = Number(body.roomId);
    const guestsCount = Number(body.guestsCount);
    const checkIn = new Date(`${body.checkIn}T00:00:00`);
    const checkOut = new Date(`${body.checkOut}T00:00:00`);
    if (!Number.isInteger(guestId) || !Number.isInteger(roomId) || !body.checkIn || !body.checkOut || !Number.isInteger(guestsCount) || guestsCount < 1 || Number.isNaN(checkIn.valueOf()) || Number.isNaN(checkOut.valueOf()) || checkOut <= checkIn) {
      return NextResponse.json({ error: "Provide valid guest, room, dates, and guest count." }, { status: 400 });
    }
    const db = getMySQL();
    await db.query("CALL sp_create_reservation(?, ?, ?, ?, ?)", [guestId, roomId, body.checkIn, body.checkOut, guestsCount]);
    const [reservationRows] = await db.query<RowDataPacket[]>("SELECT reservation_id FROM Reservation WHERE guest_id = ? AND room_id = ? ORDER BY reservation_id DESC LIMIT 1", [guestId, roomId]);
    const reservation = reservationRows[0] as { reservation_id: number } | undefined;
    if (!reservation) throw new Error("Reservation was created but could not be retrieved.");
    return NextResponse.json({ reservationId: reservation.reservation_id }, { status: 201 });
  } catch (error) {
    console.error("Reservation creation failed", error);
    const message = getErrorMessage(error);
    const status = message.startsWith("MySQL is not running") ? 503 : 400;
    return NextResponse.json({ error: message }, { status });
  }
}
