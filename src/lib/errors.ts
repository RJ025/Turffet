const MESSAGES: Record<string, string> = {
  AUTH_REQUIRED: 'Please sign in to continue.',
  PROFILE_NOT_FOUND: 'Please finish setting up your profile first.',
  BOOKING_BLOCKED: 'Booking is temporarily blocked on your account because of missed bookings.',
  COURT_NOT_FOUND: 'This court is no longer available.',
  TURF_NOT_FOUND: 'This turf is no longer listed.',
  SPORT_NOT_SUPPORTED: 'This court doesn’t support the selected sport.',
  TOO_MANY_SLOTS: 'You can book at most 3 back-to-back slots at a time.',
  INVALID_PLAYERS: 'Please check the number of players. It exceeds this court’s capacity.',
  SLOT_IN_PAST: 'That slot has already started. Pick a later time.',
  TOO_FAR_AHEAD: 'You can only book up to 14 days ahead.',
  OUTSIDE_HOURS: 'That time is outside the turf’s operating hours.',
  DAILY_LIMIT: 'You already have 2 bookings on that day. Cancel one to book another.',
  SLOT_TAKEN: 'Someone just booked that slot 😕 Please pick another one.',
  BOOKING_NOT_FOUND: 'Booking not found.',
  NOT_CANCELLABLE: 'This booking can no longer be cancelled.',
  CANCELLATION_WINDOW_PASSED: 'Free cancellation closes 2 hours before the slot starts.',
  REVIEW_NOT_ALLOWED: 'You can review a turf once your game is over.',
  INVALID_RATING: 'Please choose a rating between 1 and 5.',
  GAME_NOT_FOUND: 'This game no longer exists.',
  CANNOT_JOIN_OWN_GAME: 'You’re the host of this game.',
  GAME_NOT_OPEN: 'This game is no longer accepting players.',
  REQUEST_DECLINED: 'The host has declined your request for this game.',
  REQUEST_NOT_FOUND: 'Request not found.',
  NOT_HOST: 'Only the host can do that.',
  REQUEST_NOT_PENDING: 'This request was already handled.',
  GAME_FULL: 'All spots are filled.',
  NOT_OWNER: 'You can only manage turfs that belong to your owner account.',
  BUSINESS_NAME_REQUIRED: 'Please enter your business or venue name.',
  NAME_REQUIRED: 'Please enter a name for your turf.',
  LOCATION_REQUIRED: 'Please set your turf location on the map.',
  ADDRESS_REQUIRED: 'Please enter your turf’s area and address.',
  COURT_REQUIRED: 'Please add at least one court or pitch.',
  HOURS_REQUIRED: 'Please enable at least one open day for your turf.',
  INVALID_HOURS: 'Closing time must be later than opening time.',
  COURT_SPORT_REQUIRED: 'Please select at least one sport for every court.',
  INVALID_QR: 'Invalid QR signature. Please verify the booking code manually.',
  ALREADY_CHECKED_IN: 'This booking has already been checked in.',
  TOO_EARLY: 'Check-in opens 60 minutes before the slot starts.',
  TOO_EARLY_NO_SHOW: 'You can mark a no-show 15 minutes after the slot starts.',
  BOOKING_ENDED: 'This booking has already ended.',
  REVIEW_NEEDS_CHECKIN: 'Only players who checked in at the venue can leave a review.',
}

export function errorMessage(err: unknown): string {
  if (!err) return 'Something went wrong.'
  const raw =
    typeof err === 'string'
      ? err
      : typeof err === 'object' && err && 'message' in err
        ? String((err as { message: unknown }).message)
        : String(err)
  for (const code of Object.keys(MESSAGES)) {
    if (raw.includes(code)) return MESSAGES[code]
  }
  if (/fetch|network/i.test(raw)) return 'You seem to be offline. Check your connection and try again.'
  return raw || 'Something went wrong.'
}
