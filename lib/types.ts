export type DashboardStats = {
  arrivals: number;
  departures: number;
  occupiedRooms: number;
  totalRooms: number;
  revenue: number;
  pendingPayments: number;
};

export type Reservation = {
  reservation_id: number;
  guest_name: string;
  email: string;
  room_number: number;
  type_name: string;
  check_in: string;
  check_out: string;
  guests_count: number;
  booking_status: string;
  total_amount: number;
  amount_paid: number;
  balance_due: number;
};

export type Room = {
  room_id: number;
  room_number: number;
  type_name: string;
  price_per_night: number;
  capacity: number;
  status: string;
};
