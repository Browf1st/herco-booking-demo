// The "before you confirm" summary for the Edit service popup: which lines are added or removed and the new total.
// Pure, no imports, so Node tests can load it. The server still prices and saves the change.

export type ChangeLine = { code: string; label: string; centavos?: number; quote?: boolean };
export type ChangeSummary = {
	added: ChangeLine[]; removed: ChangeLine[]; kept: ChangeLine[];
	/** The new total in centavos, or undefined when a line has no exact price (shop quote or unknown). */
	totalCentavos?: number;
	/** Why the change cannot be confirmed yet, or '' when it can. */
	problem: string;
};

/** `current` are the booking's lines, `options` the catalog lines that may be added, `wanted` the codes ticked in the popup. */
export function summarizeServiceChange(current: readonly ChangeLine[], options: readonly ChangeLine[], wanted: readonly string[]): ChangeSummary {
	const removed = current.filter((line) => !wanted.includes(line.code));
	const kept = current.filter((line) => wanted.includes(line.code));
	const added = options.filter((line) => wanted.includes(line.code) && !current.some((existing) => existing.code === line.code));
	const final = [...kept, ...added];
	const exact = final.every((line) => !line.quote && typeof line.centavos === 'number');
	const problem = !final.length ? 'A booking needs at least one service.' : !removed.length && !added.length ? 'Nothing has changed yet.' : '';
	return { added, removed, kept, totalCentavos: exact ? final.reduce((sum, line) => sum + (line.centavos ?? 0), 0) : undefined, problem };
}
