import { NextResponse } from "next/server";
import { getMySQL } from "@/lib/db";

type RouteContext = { params: { id: string } };

export async function PATCH(request: Request, { params }: RouteContext) {
  const originalGuestId = Number(params.id);
  if (!Number.isInteger(originalGuestId) || originalGuestId < 1 || originalGuestId > 2147483647) {
    return NextResponse.json({ error: "Invalid guest ID." }, { status: 400 });
  }

  try {
    const body = await request.json() as Record<string, unknown>;
    const guestId = Number(body.guestId);
    const firstName = typeof body.firstName === "string" ? body.firstName.trim() : "";
    const lastName = typeof body.lastName === "string" ? body.lastName.trim() : "";
    if (!Number.isInteger(guestId) || guestId < 1 || guestId > 2147483647 || !firstName || firstName.length > 50 || !lastName || lastName.length > 50) {
      return NextResponse.json(
        { error: "Provide a guest ID from 1 to 2147483647 and first and last names of at most 50 characters." },
        { status: 400 }
      );
    }

    const db = getMySQL();
    const connection = await db.getConnection();
    try {
      await connection.beginTransaction();
      const [guestRows] = await connection.query(
        "SELECT guest_id, email, phone, address, date_of_birth, id_proof, created_at FROM Guest WHERE guest_id = ?",
        [originalGuestId]
      ) as [Array<Record<string, unknown>>, unknown];
      if (!guestRows.length) {
        throw new Error("Guest does not exist.");
      }

      if (guestId === originalGuestId) {
        await connection.query(
          "UPDATE Guest SET first_name = ?, last_name = ? WHERE guest_id = ?",
          [firstName, lastName, originalGuestId]
        );
      } else {
        const [usedRows] = await connection.query(
          "SELECT guest_id FROM Guest WHERE guest_id = ?",
          [guestId]
        ) as [Array<Record<string, unknown>>, unknown];
        if (usedRows.length) {
          throw new Error("Guest ID is already in use.");
        }

        const guest = guestRows[0];
        const temporaryEmail = `guest-${guestId}-${Date.now()}@temporary.local`;
        await connection.query(
          "INSERT INTO Guest (guest_id, first_name, last_name, email, phone, address, date_of_birth, id_proof, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [
            guestId,
            firstName,
            lastName,
            temporaryEmail,
            guest.phone,
            guest.address,
            guest.date_of_birth,
            guest.id_proof,
            guest.created_at
          ]
        );
        await connection.query(
          "UPDATE Reservation SET guest_id = ? WHERE guest_id = ?",
          [guestId, originalGuestId]
        );
        await connection.query("DELETE FROM Guest WHERE guest_id = ?", [originalGuestId]);
        await connection.query("UPDATE Guest SET email = ? WHERE guest_id = ?", [guest.email, guestId]);
      }
      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }
    return NextResponse.json({ guestId });
  } catch (error) {
    console.error("Guest update failed", error);
    const message = error instanceof Error && error.message
      ? error.message
      : "Guest could not be updated.";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
