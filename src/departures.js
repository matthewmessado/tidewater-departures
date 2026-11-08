// Scheduled departures for the sample API. A real service would read these from a
// booking database; a fixed list keeps the project focused on shipping, not storage.
const schedule = [
  {
    id: 'dep-101',
    tourId: 'sunset-harbour-cruise',
    tourName: 'Sunset Harbour Cruise',
    departsAt: '2026-11-13T17:30:00-05:00',
    seatsTotal: 24,
    seatsBooked: 19,
  },
  {
    id: 'dep-102',
    tourId: 'sunset-harbour-cruise',
    tourName: 'Sunset Harbour Cruise',
    departsAt: '2026-11-14T17:30:00-05:00',
    seatsTotal: 24,
    seatsBooked: 24,
  },
  {
    id: 'dep-201',
    tourId: 'mangrove-kayak',
    tourName: 'Mangrove Kayak Safari',
    departsAt: '2026-11-14T08:00:00-05:00',
    seatsTotal: 10,
    seatsBooked: 6,
  },
  {
    id: 'dep-301',
    tourId: 'lighthouse-walk',
    tourName: 'Lighthouse Heritage Walk',
    departsAt: '2026-11-15T10:00:00-05:00',
    seatsTotal: 30,
    seatsBooked: 12,
  },
  {
    id: 'dep-401',
    tourId: 'dolphin-watch',
    tourName: 'Morning Dolphin Watch',
    departsAt: '2026-11-16T07:00:00-05:00',
    seatsTotal: 16,
    seatsBooked: 3,
  },
];

// Seats left and sold-out are worked out on every request rather than stored,
// so they can never disagree with the booked count.
function withAvailability(departure) {
  const seatsLeft = departure.seatsTotal - departure.seatsBooked;
  return { ...departure, seatsLeft, soldOut: seatsLeft === 0 };
}

export function listDepartures({ tour } = {}) {
  const matching = tour ? schedule.filter((d) => d.tourId === tour) : schedule;
  return matching.map(withAvailability);
}

export function findDeparture(id) {
  const departure = schedule.find((d) => d.id === id);
  return departure ? withAvailability(departure) : null;
}
