import { NextResponse } from "next/server";
import { getMySQL } from "@/lib/db";
import { RowDataPacket } from "mysql2";
import type { DashboardStats, Reservation, Room } from "@/lib/types";

export const dynamic = "force-dynamic";

function getErrorMessage(error: unknown) {
  if (error instanceof AggregateError) {
    const firstError = error.errors[0];
    if (firstError && typeof firstError === "object" && "code" in firstError && firstError.code === "ECONNREFUSED") {
      return "MySQL is not running or is not reachable at MYSQL_URL. Start MySQL and try again.";
    }
  }
  return error instanceof Error && error.message ? error.message : "Database query failed.";
}

export async function GET() {
  try {
    const db = getMySQL();
    const [statsRows] = await db.query<RowDataPacket[]>("SELECT (SELECT COUNT(*) FROM Reservation WHERE check_in = CURDATE() AND booking_status IN ('Confirmed','Pending')) AS arrivals, (SELECT COUNT(*) FROM Reservation WHERE check_out = CURDATE() AND booking_status IN ('Confirmed','Checked-in')) AS departures, (SELECT COUNT(*) FROM Room WHERE status = 'Occupied') AS occupiedRooms, (SELECT COUNT(*) FROM Room WHERE status <> 'Unavailable') AS totalRooms, (SELECT COALESCE(SUM(amount), 0) AS revenue FROM Payment WHERE payment_status = 'Successful' AND MONTH(payment_date) = MONTH(CURRENT_DATE()) AND YEAR(payment_date) = YEAR(CURRENT_DATE())), (SELECT COALESCE(SUM(balance_due), 0) FROM v_active_reservations) AS pendingPayments");
    const stats = statsRows[0];
    const [reservations] = await db.query("SELECT * FROM v_active_reservations ORDER BY check_in, reservation_id LIMIT 20");
    const [rooms] = await db.query("SELECT rm.room_id, rm.room_number, rt.type_name, rt.price_per_night, rt.capacity, rm.status FROM Room rm JOIN Room_Type rt ON rt.room_type_id = rm.room_type_id ORDER BY rm.room_number");
    const row = stats as Record<string, number>;
    const dashboardStats: DashboardStats = { arrivals: row.arrivals ?? 0, departures: row.departures ?? 0, occupiedRooms: row.occupiedRooms ?? 0, totalRooms: row.totalRooms ?? 0, revenue: row.revenue ?? 0, pendingPayments: row.pendingPayments ?? 0 };
    return NextResponse.json({ stats: dashboardStats, reservations: reservations as Reservation[], rooms: rooms as Room[] });
  } catch (error) {
    console.error("Dashboard query failed", error);
    return NextResponse.json({ error: getErrorMessage(error) }, { status: 503 });
  }
}
