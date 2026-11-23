// Staff HERCO Points ranking (owner item 11, 2026-11-23): the # number is always the fan's
// points rank, whatever sort or search is used. The server returns members ordered by
// balance (highest first, then name, then id), so the position in the unsearched list is the rank.
export type RankedMember = { id: string; name: string; balance: number };
export function rankMap(members: readonly { id: string }[]): Map<string, number> {
	return new Map(members.map((member, index) => [member.id, index + 1]));
}

export function sortMembers<M extends RankedMember>(members: readonly M[], sort: string, ranks: ReadonlyMap<string, number>): M[] {
	const rank = (member: M) => ranks.get(member.id) ?? Number.MAX_SAFE_INTEGER;
	return members.toSorted((a, b) =>
		sort === 'name' ? a.name.localeCompare(b.name) || rank(a) - rank(b)
			: sort === 'lowest' ? a.balance - b.balance || rank(b) - rank(a)
				: b.balance - a.balance || rank(a) - rank(b));
}
