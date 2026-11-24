// Thrown when the server says someone else changed the opening hours first. Kept tiny so the booking page can import it cheaply.
export class ScheduleChanged extends Error {}
