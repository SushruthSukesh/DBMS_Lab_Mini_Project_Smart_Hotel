"use client";

import { useEffect, useMemo, useState } from "react";
import type { DashboardStats, Reservation, Room } from "@/lib/types";

const initialStats: DashboardStats = {
  arrivals: 0,
  departures: 0,
  occupiedRooms: 0,
  totalRooms: 0,
  revenue: 0,
  pendingPayments: 0
};

function formatCurrency(value: number) {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0
  }).format(value);
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("en-IN", { day: "2-digit", month: "short" }).format(
    new Date(`${value}T00:00:00`)
  );
}

export default function Home() {
  const [stats, setStats] = useState(initialStats);
  const [reservations, setReservations] = useState<Reservation[]>([]);
  const [rooms, setRooms] = useState<Room[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [activeTab, setActiveTab] = useState<"overview" | "rooms" | "reservations">("overview");
  const [showBooking, setShowBooking] = useState(false);
  const [bookingMessage, setBookingMessage] = useState("");
  const [bookingPending, setBookingPending] = useState(false);
  const [search, setSearch] = useState("");

  async function loadDashboard() {
    setLoading(true);
    setError("");
    try {
      const response = await fetch("/api/dashboard", { cache: "no-store" });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error ?? "Unable to load dashboard.");
      setStats(payload.stats);
      setReservations(payload.reservations);
      setRooms(payload.rooms);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Unable to connect to the database.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadDashboard();
  }, []);

  const filteredReservations = useMemo(
    () =>
      reservations.filter((item) =>
        `${item.guest_name} ${item.room_number} ${item.booking_status}`
          .toLowerCase()
          .includes(search.toLowerCase())
      ),
    [reservations, search]
  );

  async function createBooking(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (bookingPending) return;
    setBookingMessage("");
    const form = new FormData(event.currentTarget);
    const payload = Object.fromEntries(form.entries());
    const checkIn = String(payload.checkIn);
    const checkOut = String(payload.checkOut);
    if (!checkIn || !checkOut || checkOut <= checkIn) {
      setBookingMessage("Check-out must be after check-in.");
      return;
    }
    setBookingPending(true);
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 10000);
    try {
      const response = await fetch("/api/reservations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: controller.signal
      });
      const result = await response.json();
      if (!response.ok) {
        setBookingMessage(result.error ?? "Booking could not be created.");
        return;
      }
      setBookingMessage(`Reservation #${result.reservationId} confirmed.`);
      event.currentTarget.reset();
      await loadDashboard();
    } catch (caught) {
      setBookingMessage(caught instanceof DOMException && caught.name === "AbortError"
        ? "The request timed out. Check that MySQL is running and try again."
        : "Unable to reach the booking service. Check that the backend and MySQL are running.");
    } finally {
      window.clearTimeout(timeout);
      setBookingPending(false);
    }
  }

  return (
    <main className="shell">
      <aside className="sidebar">
        <div className="brand"><span className="brand-mark">S</span><span>SmartStay</span></div>
        <div className="property"><span className="live-dot" /> Bengaluru Central <span>⌄</span></div>
        <nav>
          <button className={activeTab === "overview" ? "nav-item active" : "nav-item"} onClick={() => setActiveTab("overview")}>◈ <span>Overview</span></button>
          <button className={activeTab === "reservations" ? "nav-item active" : "nav-item"} onClick={() => setActiveTab("reservations")}>▣ <span>Reservations</span><b>{reservations.length}</b></button>
          <button className={activeTab === "rooms" ? "nav-item active" : "nav-item"} onClick={() => setActiveTab("rooms")}>▤ <span>Rooms & inventory</span></button>
          <button className="nav-item" onClick={() => setShowBooking(true)}>＋ <span>New reservation</span></button>
        </nav>
        <div className="sidebar-bottom">
          <button className="nav-item">⚙ <span>Settings</span></button>
          <div className="user-card"><div className="avatar">AS</div><div><strong>Admin Staff</strong><small>Administrator</small></div><span>⋮</span></div>
        </div>
      </aside>

      <section className="content">
        <header className="topbar"><div className="mobile-brand">SmartStay</div><div className="top-actions"><button className="icon-btn">⌕</button><button className="icon-btn">♧<i /></button><div className="avatar small">AS</div></div></header>
        <div className="page-heading"><div><p className="eyebrow">WEDNESDAY, 29 OCTOBER 2026</p><h1>Good morning, Admin <span>✦</span></h1><p className="muted">Here&apos;s what&apos;s happening at your property today.</p></div><button className="primary" onClick={() => setShowBooking(true)}>＋ New reservation</button></div>
        {error && <div className="alert"><strong>Database connection required</strong><span>{error}</span><button onClick={loadDashboard}>Retry</button></div>}
        {loading ? <div className="loading">Loading your hotel overview…</div> : <>
          <div className="metrics">
            <Metric label="Today&apos;s arrivals" value={stats.arrivals} hint="Expected check-ins" icon="↘" tone="blue" />
            <Metric label="Today&apos;s departures" value={stats.departures} hint="Expected check-outs" icon="↗" tone="orange" />
            <Metric label="Occupancy rate" value={`${stats.totalRooms ? Math.round((stats.occupiedRooms / stats.totalRooms) * 100) : 0}%`} hint={`${stats.occupiedRooms} of ${stats.totalRooms} rooms occupied`} icon="◉" tone="purple" />
            <Metric label="Revenue this month" value={formatCurrency(stats.revenue)} hint={`${formatCurrency(stats.pendingPayments)} pending`} icon="₹" tone="green" />
          </div>
          {activeTab === "overview" && <div className="grid-layout"><section className="panel wide"><PanelHeading title="Upcoming reservations" link="View all" onClick={() => setActiveTab("reservations")} /><ReservationTable data={reservations.slice(0, 5)} /></section><section className="panel"><PanelHeading title="Room status" link="Manage rooms" onClick={() => setActiveTab("rooms")} /><div className="room-summary"><div className="donut" style={{ "--progress": `${stats.totalRooms ? (stats.occupiedRooms / stats.totalRooms) * 100 : 0}%` } as React.CSSProperties}><strong>{stats.totalRooms ? Math.round((stats.occupiedRooms / stats.totalRooms) * 100) : 0}%</strong><small>occupied</small></div><div className="legend"><span><i className="dot occupied" />Occupied <b>{stats.occupiedRooms}</b></span><span><i className="dot available" />Available <b>{Math.max(stats.totalRooms - stats.occupiedRooms, 0)}</b></span></div></div></section><section className="panel wide"><PanelHeading title="Quick actions" /><div className="quick-actions"><button onClick={() => setShowBooking(true)}><span className="quick-icon violet">＋</span><strong>New reservation</strong><small>Create a guest booking</small></button><button onClick={() => setActiveTab("rooms")}><span className="quick-icon teal">⌂</span><strong>Room availability</strong><small>View live inventory</small></button><button onClick={() => setActiveTab("reservations")}><span className="quick-icon yellow">▤</span><strong>Guest directory</strong><small>Search guest profiles</small></button></div></section></div>}
          {activeTab === "reservations" && <section className="panel full-panel"><PanelHeading title="All reservations" /><div className="toolbar"><input placeholder="Search guest, room or status…" value={search} onChange={(event) => setSearch(event.target.value)} /><button className="filter">☷ Filter</button></div><ReservationTable data={filteredReservations} /></section>}
          {activeTab === "rooms" && <section className="panel full-panel"><PanelHeading title="Room inventory" /><div className="room-grid">{rooms.map((room) => <div className="room-card" key={room.room_id}><div><span className={`status ${room.status.toLowerCase()}`}>{room.status}</span><h3>Room {room.room_number}</h3><p>{room.type_name} · Up to {room.capacity} guests</p></div><strong>{formatCurrency(room.price_per_night)}<small>/night</small></strong></div>)}</div></section>}
        </>}
        <footer>SmartStay Operations <span>•</span> Data is synced with MySQL and MongoDB through secured API routes.</footer>
      </section>
      {showBooking && <div className="modal-backdrop" onMouseDown={(event) => event.target === event.currentTarget && !bookingPending && setShowBooking(false)}><form className="modal" onSubmit={createBooking}><button type="button" className="modal-close" disabled={bookingPending} onClick={() => setShowBooking(false)}>×</button><p className="eyebrow">RESERVATION DESK</p><h2>Create a reservation</h2><p className="muted">The booking procedure calculates the total and prevents double-booking.</p><div className="form-grid"><label>Guest ID<input name="guestId" type="number" min="1" placeholder="1" required /></label><label>Room ID<input name="roomId" type="number" min="1" placeholder="1" required /></label><label>Check-in<input name="checkIn" type="date" min={new Date().toISOString().slice(0, 10)} required /></label><label>Check-out<input name="checkOut" type="date" min={new Date().toISOString().slice(0, 10)} required /></label><label>Guests<input name="guestsCount" type="number" min="1" defaultValue="1" required /></label></div>{bookingMessage && <div className={bookingMessage.startsWith("Reservation #") ? "form-message success" : "form-message"}>{bookingMessage}</div>}<button className="primary submit" disabled={bookingPending} type="submit">{bookingPending ? "Confirming…" : "Confirm reservation"}</button></form></div>}
    </main>
  );
}

function Metric({ label, value, hint, icon, tone }: { label: string; value: string | number; hint: string; icon: string; tone: string }) {
  return <div className="metric"><div className={`metric-icon ${tone}`}>{icon}</div><div><p>{label}</p><strong>{value}</strong><small>{hint}</small></div><span className="trend">↗</span></div>;
}

function PanelHeading({ title, link, onClick }: { title: string; link?: string; onClick?: () => void }) {
  return <div className="panel-heading"><h2>{title}</h2>{link && <button onClick={onClick}>{link} →</button>}</div>;
}

function ReservationTable({ data }: { data: Reservation[] }) {
  if (!data.length) return <div className="empty">No reservations found. Create your first booking to see it here.</div>;
  return <div className="table-wrap"><table><thead><tr><th>Guest</th><th>Room</th><th>Stay</th><th>Status</th><th className="align-right">Amount</th></tr></thead><tbody>{data.map((item) => <tr key={item.reservation_id}><td><div className="guest-cell"><span className="guest-avatar">{item.guest_name.split(" ").map((word) => word[0]).join("").slice(0, 2)}</span><div><strong>{item.guest_name}</strong><small>{item.email}</small></div></div></td><td><strong>#{item.room_number}</strong><small>{item.type_name}</small></td><td>{formatDate(item.check_in)} – {formatDate(item.check_out)}<small>{item.guests_count} guests</small></td><td><span className={`status ${item.booking_status.toLowerCase().replace("-", "")}`}>{item.booking_status}</span></td><td className="align-right"><strong>{formatCurrency(item.total_amount)}</strong><small>{item.balance_due ? `${formatCurrency(item.balance_due)} due` : "Paid"}</small></td></tr>)}</tbody></table></div>;
}
