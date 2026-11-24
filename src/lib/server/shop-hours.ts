export type ShopHours = { openHour: number; closeHour: number; openWeekdays: number[] };

// Checks the database answer and keeps only the three public fields. Returns null if it looks wrong.
export function toShopHours(data: unknown): ShopHours | null {
	if (!data || typeof data !== 'object') return null;
	const { openHour, closeHour, openWeekdays } = data as Record<string, unknown>;
	if (!Number.isInteger(openHour) || !Number.isInteger(closeHour)) return null;
	const open = openHour as number;
	const close = closeHour as number;
	if (open < 0 || open > 23 || close < 1 || close > 24 || close <= open) return null;
	if (!Array.isArray(openWeekdays) || openWeekdays.length < 1 || openWeekdays.length > 7) return null;
	if (!openWeekdays.every((day) => Number.isInteger(day) && day >= 0 && day <= 6)) return null;
	return { openHour: open, closeHour: close, openWeekdays: [...new Set(openWeekdays as number[])].sort((a, b) => a - b) };
}
