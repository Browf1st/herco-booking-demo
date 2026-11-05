import { demoFans, rewardProgram } from './config';

export type RewardService = 'ceramic' | 'powder';
export type RewardReceipt = {
	id: string;
	reference: string;
	memberId: string;
	memberName: string;
	reward: string;
	cost: number;
	balanceBefore: number;
	balanceAfter: number;
	at: string;
	status: 'issued' | 'claimed';
	claimedAt?: string;
};
export type Member = { id: string; name: string; phone: string; demoFan?: boolean };
type PointEntry = { id: string; memberId: string; amount: number; reason: string; at: string };
type Redemption = { id: string; memberId: string; service: RewardService; cost: number; status: 'requested' | 'fulfilled' | 'rejected'; at: string };
type StockItem = { id: string; name: string; unit: string; quantity: number; minimum: number };
type StockEntry = { id: string; itemId: string; amount: number; reason: string; at: string };
type Payment = { id: string; bookingId: string; amount: number; method: string; at: string };
export type RewardTier = { points: number; name: string; scope?: string };
type Operations = {
	rewardProgram: RewardTier[];
	fanSamplesVersion?: number;
	inventorySamplesVersion?: number;
	members: Member[];
	points: PointEntry[];
	redemptions: Redemption[];
	rewardReceipts: RewardReceipt[];
	stock: StockItem[];
	stockEntries: StockEntry[];
	payments: Payment[];
	rewardCosts: Record<RewardService, number>;
};

const KEY = 'herco-operations-v1';
const empty = (): Operations => ({
	rewardProgram: rewardProgram.map((reward) => ({ ...reward })),
	members: [], points: [], redemptions: [], rewardReceipts: [], stock: [], stockEntries: [], payments: [],
	rewardCosts: { ceramic: 0, powder: 0 }
});
function load(): Operations {
	if (typeof localStorage === 'undefined') return empty();
	const saved = localStorage.getItem(KEY);
	const data: Operations = saved ? { ...empty(), ...JSON.parse(saved) } : empty();
	if (data.fanSamplesVersion !== 1) {
		demoFans.forEach((fan, index) => {
			const memberId = `DEMO-FAN-${index + 1}`;
			data.members.push({ id: memberId, name: fan.name, phone: '', demoFan: true });
			data.points.push({ id: `DEMO-POINTS-${index + 1}`, memberId, amount: fan.points, reason: 'Sample HERCO Points balance', at: '2026-11-05T00:00:00.000Z' });
		});
		data.fanSamplesVersion = 1;
		localStorage.setItem(KEY, JSON.stringify(data));
	}
	if (data.inventorySamplesVersion !== 1) {
		const supplies = [
			{ name: 'Ceramic coating · 30 ml', unit: 'bottle', quantity: 6, minimum: 2 },
			{ name: 'Panel preparation / IPA wipe', unit: 'litre', quantity: 4, minimum: 1 },
			{ name: 'Microfibre towels', unit: 'piece', quantity: 24, minimum: 8 },
			{ name: 'Coating applicator pads', unit: 'piece', quantity: 3, minimum: 5 },
			{ name: 'Surface preparation compound', unit: 'bottle', quantity: 4, minimum: 1 },
			{ name: 'Polishing pads', unit: 'piece', quantity: 12, minimum: 4 },
			{ name: 'Purple powder coating', unit: 'kg', quantity: 2.5, minimum: 1 },
			{ name: 'Pink powder coating', unit: 'kg', quantity: 0.5, minimum: 1 },
			{ name: 'Blue powder coating', unit: 'kg', quantity: 3, minimum: 1 },
			{ name: 'Red powder coating', unit: 'kg', quantity: 2, minimum: 1 },
			{ name: 'High-temperature masking tape', unit: 'roll', quantity: 8, minimum: 3 },
			{ name: 'Silicone masking plugs', unit: 'set', quantity: 4, minimum: 2 }
		];
		supplies.forEach((item, index) => {
			const itemId = 'DEMO-STOCK-' + (index + 1);
			if (data.stock.some((existing) => existing.id === itemId || existing.name.toLowerCase() === item.name.toLowerCase())) return;
			data.stock.push({ id: itemId, ...item });
			data.stockEntries.push({ id: 'DEMO-OPENING-' + (index + 1), itemId, amount: item.quantity, reason: 'Sample opening stock', at: '2026-11-05T00:00:00.000Z' });
		});
		data.inventorySamplesVersion = 1;
		localStorage.setItem(KEY, JSON.stringify(data));
	}
	return data;
}
export const ops = $state<{ data: Operations }>({ data: load() });
const id = () => crypto.randomUUID();
const timestamp = () => new Date().toISOString();

// Persist the complete change before publishing it to the UI.
function commit(update: (draft: Operations) => void) {
	const draft = load();
	update(draft);
	localStorage.setItem(KEY, JSON.stringify(draft));
	ops.data = draft;
}
export function syncOperations() {
	const sync = (event: StorageEvent) => {
		if (event.storageArea === localStorage && (event.key === KEY || event.key === null)) ops.data = load();
	};
	window.addEventListener('storage', sync);
	return () => window.removeEventListener('storage', sync);
}
export function resetDemoPointsOnRefresh() {
	const navigation = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming | undefined;
	if (navigation?.type !== 'reload' || !window.location.pathname.replace(/\/$/, '').endsWith('/points')) return;
	const memberId = 'DEMO-FAN-1';
	commit((data) => {
		if (!data.members.some((member) => member.id === memberId && member.demoFan)) return;
		data.points = data.points.filter((entry) => entry.memberId !== memberId);
		data.points.push({ id: 'DEMO-POINTS-1', memberId, amount: 1280, reason: 'Sample HERCO Points balance', at: timestamp() });
		data.rewardReceipts = data.rewardReceipts.filter((receipt) => receipt.memberId !== memberId);
		data.redemptions = data.redemptions.filter((request) => request.memberId !== memberId);
	});
}
function balanceIn(data: Operations, memberId: string) {
	return data.points.filter((entry) => entry.memberId === memberId).reduce((sum, entry) => sum + entry.amount, 0);
}
export const pointBalance = (memberId: string) => balanceIn(ops.data, memberId);
export const fanRanking = () => ops.data.members.toSorted((a, b) => pointBalance(b.id) - pointBalance(a.id) || a.name.localeCompare(b.name));
export const rewardName = (service: RewardService) => service === 'ceramic' ? 'Free ceramic coating' : 'Free powder coating';
export async function redeemReward(memberId: string, rewardPoints: number, requestId: string) {
	const issue = () => {
		let receipt: RewardReceipt | undefined;
		commit((data) => {
			const existing = data.rewardReceipts.find((item) => item.id === requestId);
			if (existing) {
				if (existing.memberId !== memberId || existing.cost !== rewardPoints) throw new Error('This redemption reference is already used.');
				receipt = existing;
				return;
			}
			const member = data.members.find((item) => item.id === memberId);
			const reward = data.rewardProgram.find((item) => item.points === rewardPoints);
			if (!member || !reward || !requestId) throw new Error('Choose a valid account and reward.');
			const balanceBefore = balanceIn(data, memberId);
			if (balanceBefore < reward.points) throw new Error('You need more HERCO Points for this reward.');
			const at = timestamp();
			receipt = {
				id: requestId, reference: 'AR-' + requestId.toUpperCase(), memberId, memberName: member.name,
				reward: reward.name + (reward.scope ? ' · ' + reward.scope : ''), cost: reward.points,
				balanceBefore, balanceAfter: balanceBefore - reward.points, at, status: 'issued'
			};
			data.rewardReceipts.push(receipt);
			data.points.push({ id: id(), memberId, amount: -reward.points, reason: receipt.reward + ' redeemed · ' + receipt.reference, at });
		});
		return receipt!;
	};
	// Serialize redemptions across tabs of the local demo.
	if (typeof navigator !== 'undefined' && navigator.locks) return navigator.locks.request('herco-reward-redemption', async () => issue());
	return issue();
}
export function claimRewardReceipt(receiptId: string) {
	commit((data) => {
		const receipt = data.rewardReceipts.find((item) => item.id === receiptId);
		if (!receipt || receipt.status !== 'issued') throw new Error('This AR has already been claimed or was not found.');
		receipt.status = 'claimed';
		receipt.claimedAt = timestamp();
	});
}
export function editRewardTier(index: number, reward: RewardTier) {
	if (!reward.name.trim() || !Number.isSafeInteger(reward.points) || reward.points <= 0) throw new Error('Enter a reward name and positive whole points.');
	commit((data) => {
		if (!Number.isInteger(index) || !data.rewardProgram[index]) throw new Error('Reward not found.');
		if (data.rewardProgram.some((item, i) => i !== index && item.points === reward.points)) throw new Error('Each reward must have a different points requirement.');
		data.rewardProgram[index] = { name: reward.name.trim(), points: reward.points, scope: reward.scope?.trim() || undefined };
	});
}
export function grantPoints(memberId: string, amount: number, reason = 'HERCO Points added by admin') {
	if (!Number.isSafeInteger(amount) || amount <= 0 || !reason.trim()) throw new Error('Enter positive whole points and a reason.');
	commit((data) => {
		if (!data.members.some((member) => member.id === memberId)) throw new Error('Member not found.');
		data.points.push({ id: id(), memberId, amount, reason: reason.trim(), at: timestamp() });
	});
}
export function setRewardCosts(ceramic: number, powder: number) {
	if (![ceramic, powder].every((cost) => Number.isSafeInteger(cost) && cost >= 0)) throw new Error('Use whole point amounts of zero or more.');
	commit((data) => { data.rewardCosts = { ceramic, powder }; });
}
export function redeem(memberId: string, service: RewardService) {
	commit((data) => {
		const cost = data.rewardCosts[service];
		if (!data.members.some((member) => member.id === memberId)) throw new Error('Member not found.');
		if (!cost || balanceIn(data, memberId) < cost) throw new Error('This reward is unavailable or you need more points.');
		if (data.redemptions.some((item) => item.memberId === memberId && item.status === 'requested')) throw new Error('Your existing reward request is awaiting review.');
		const requestId = id();
		data.redemptions.push({ id: requestId, memberId, service, cost, status: 'requested', at: timestamp() });
		data.points.push({ id: id(), memberId, amount: -cost, reason: rewardName(service) + ' requested', at: timestamp() });
	});
}
export function reviewRedemption(requestId: string, status: 'fulfilled' | 'rejected') {
	commit((data) => {
		const request = data.redemptions.find((item) => item.id === requestId);
		if (!request || request.status !== 'requested') throw new Error('This request has already been reviewed.');
		request.status = status;
		if (status === 'rejected') data.points.push({
			id: id(), memberId: request.memberId, amount: request.cost, reason: 'Reward request declined. Points returned.', at: timestamp()
		});
	});
}
export function addStock(name: string, unit: string, quantity: number, minimum: number) {
	if (!name.trim() || !unit.trim() || ![quantity, minimum].every((n) => Number.isFinite(n) && n >= 0)) throw new Error('Enter an item, unit, and valid stock amounts.');
	commit((data) => {
		if (data.stock.some((item) => item.name.toLowerCase() === name.trim().toLowerCase())) throw new Error('This item already exists. Use Add stock to increase its quantity.');
		const itemId = id();
		data.stock.push({ id: itemId, name: name.trim(), unit: unit.trim(), quantity, minimum });
		data.stockEntries.push({ id: id(), itemId, amount: quantity, reason: 'Opening stock', at: timestamp() });
	});
}
export function adjustStock(itemId: string, amount: number, reason: string) {
	if (!Number.isFinite(amount) || !amount || !reason.trim()) throw new Error('Enter a stock adjustment and reason.');
	commit((data) => {
		const item = data.stock.find((item) => item.id === itemId);
		if (!item || item.quantity + amount < 0) throw new Error('Stock cannot go below zero.');
		item.quantity = Math.round((item.quantity + amount) * 1000) / 1000;
		data.stockEntries.push({ id: id(), itemId, amount, reason: reason.trim(), at: timestamp() });
	});
}
export function recordPayment(bookingId: string, amount: number, method: string) {
	if (!bookingId || !Number.isFinite(amount) || amount <= 0 || !method) throw new Error('Select a booking and enter a positive payment.');
	commit((data) => data.payments.push({ id: id(), bookingId, amount: Math.round(amount * 100) / 100, method, at: timestamp() }));
}
