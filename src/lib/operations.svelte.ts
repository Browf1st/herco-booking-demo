import { demoFans, rewardProgram } from './config';
import { activityEvent, type ActivityEvent, type ActivityModule } from './activity';

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
	status: 'pending' | 'approved' | 'issued' | 'claimed';
	claimedAt?: string;
	claimedBy?: string;
};
export type Member = { id: string; name: string; phone: string; email?: string; demoFan?: boolean };
type PointEntry = { id: string; memberId: string; amount: number; reason: string; at: string };
type Redemption = { id: string; memberId: string; service: RewardService; cost: number; status: 'requested' | 'fulfilled' | 'rejected'; at: string };
export type StockDetails = { unitCost?: number; billingRate?: number; capacity?: number; supplier?: string; location?: string };
type StockItem = { id: string; name: string; unit: string; quantity: number; minimum: number; category?: string; details?: StockDetails };
type StockEntry = { id: string; itemId: string; amount: number; reason: string; at: string };

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
	events: ActivityEvent[];
	stockUnits: string[];
	stockCategories: string[];

	rewardCosts: Record<RewardService, number>;
};

const KEY = 'herco-operations-v1';
const empty = (): Operations => ({
	rewardProgram: rewardProgram.map((reward) => ({ ...reward })),
	members: [], points: [], redemptions: [], rewardReceipts: [], stock: [], stockEntries: [],
	stockUnits: ['bottle'], stockCategories: [], events: [],
	rewardCosts: { ceramic: 0, powder: 0 }
});
function load(): Operations {
	if (typeof localStorage === 'undefined') return empty();
	const saved = localStorage.getItem(KEY);
	const stored = saved ? JSON.parse(saved) : {};
	const hadPayments = 'payments' in stored;
	delete stored.payments;
	const data: Operations = { ...empty(), ...stored };
	if (hadPayments) localStorage.setItem(KEY, JSON.stringify(data));
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

function logOperation(data: Operations, module: ActivityModule, action: string, target: string, detail?: string, actor?: string) {
	data.events.push(activityEvent(module, action, { target, detail }, actor));
}

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
				balanceBefore, balanceAfter: balanceBefore - reward.points, at, status: 'pending'
			};
			data.rewardReceipts.push(receipt);
			data.points.push({ id: id(), memberId, amount: -reward.points, reason: receipt.reward + ' redeemed · ' + receipt.reference, at });
			logOperation(data, 'Redemptions', 'Requested reward redemption', receipt.reference, member.name + ' · ' + receipt.reward + ' · ' + receipt.cost + ' points', 'Customer');
		});
		return receipt!;
	};
	// Serialize redemptions across tabs of the local demo.
	if (typeof navigator !== 'undefined' && navigator.locks) return navigator.locks.request('herco-reward-redemption', async () => issue());
	return issue();
}
export function saveFanProfile({ id, name, email, phone = '' }: { id: string; name: string; email: string; phone?: string }) {
	const existing = ops.data.members.find(member => member.id === id);
	if (existing?.name === name && existing.email === email && existing.phone === phone) return;
	commit(data => {
		const member = data.members.find(member => member.id === id);
		if (member) Object.assign(member, { name, email, phone });
		else data.members.push({ id, name, email, phone });
		logOperation(data, 'Customers', member ? 'Updated fan profile' : 'Registered fan profile', name, undefined, 'Customer');
	});
}

export function rewardStatus(receipt: RewardReceipt) {
	if (receipt.status === 'pending') return 'Pending for approval';
	return receipt.status === 'claimed' ? 'Claimed' : 'Approved';
}

export function approveRewardReceipt(receiptId: string) {
	commit(data => {
		const receipt = data.rewardReceipts.find(item => item.id === receiptId);
		if (!receipt || receipt.status !== 'pending') throw new Error('This request is no longer pending.');
		receipt.status = 'approved';
		logOperation(data, 'Redemptions', 'Approved redemption', receipt.reference, receipt.memberName + ' · ' + receipt.reward);
	});
}

export function claimRewardReceipt(receiptId: string) {
	commit((data) => {
		const receipt = data.rewardReceipts.find((item) => item.id === receiptId);
		if (!receipt || (receipt.status !== 'issued' && receipt.status !== 'approved')) throw new Error('Only approved rewards can be marked as claimed.');
		receipt.status = 'claimed';
		receipt.claimedAt = timestamp();
		receipt.claimedBy = 'Demo admin';
		logOperation(data, 'Redemptions', 'Marked reward as claimed', receipt.reference, receipt.memberName + ' · ' + receipt.reward);
	});
}
export function editRewardTier(index: number, reward: RewardTier) {
	if (!reward.name.trim() || !Number.isSafeInteger(reward.points) || reward.points <= 0) throw new Error('Enter a reward name and positive whole points.');
	commit((data) => {
		if (!Number.isInteger(index) || !data.rewardProgram[index]) throw new Error('Reward not found.');
		if (data.rewardProgram.some((item, i) => i !== index && item.points === reward.points)) throw new Error('Each reward must have a different points requirement.');
		const previous = data.rewardProgram[index];
		const updated = { name: reward.name.trim(), points: reward.points, scope: reward.scope?.trim() || undefined };
		data.rewardProgram[index] = updated;
		const describe = (tier: RewardTier) => [tier.name, tier.scope, tier.points + ' points'].filter(Boolean).join(' · ');
		logOperation(data, 'Rewards program', 'Edited reward tier', updated.name, describe(previous) + ' → ' + describe(updated));
	});
}
export function grantPoints(memberId: string, amount: number, reason = 'HERCO Points added by admin') {
	if (!Number.isSafeInteger(amount) || amount <= 0 || !reason.trim()) throw new Error('Enter positive whole points and a reason.');
	recordPointAdjustment(memberId, amount, reason.trim());
}

export function correctPoints(memberId: string, amount: number, reason: string) {
	if (!Number.isSafeInteger(amount) || amount === 0 || !reason.trim()) throw new Error('Enter a nonzero whole-point adjustment and a reason.');
	recordPointAdjustment(memberId, amount, 'Points correction · ' + reason.trim(), true);
}

function recordPointAdjustment(memberId: string, amount: number, reason: string, correction = false) {
	commit((data) => {
		const member = data.members.find(member => member.id === memberId);
		if (!member) throw new Error('Member not found.');
		const balance = balanceIn(data, memberId) + amount;
		if (!Number.isSafeInteger(balance) || balance < 0) throw new Error('The resulting balance must be a valid non-negative whole number.');
		data.points.push({ id: id(), memberId, amount, reason, at: timestamp() });
		logOperation(data, 'HERCO Points', correction ? 'Corrected points' : 'Added points', member.name,
			(balance - amount) + ' → ' + balance + ' points · ' + reason);
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
export function stockOptions(data: Operations, kind: 'unit' | 'category') {
	const saved = kind === 'unit' ? data.stockUnits : data.stockCategories;
	const used = data.stock.map(item => item[kind]).filter((value): value is string => Boolean(value));
	return [...new Set([...saved, ...used])].sort((a, b) => a.localeCompare(b));
}

export function addStockOption(kind: 'unit' | 'category', value: string) {
	const name = value.trim();
	if (!name) throw new Error('Enter a ' + kind + ' name.');
	commit(data => {
		if (stockOptions(data, kind).some(option => option.toLowerCase() === name.toLowerCase())) {
			throw new Error('This ' + kind + ' already exists.');
		}
		const options = kind === 'unit' ? data.stockUnits : data.stockCategories;
		options.push(name);
		logOperation(data, 'Inventory', 'Added ' + kind, name);
	});
}

export function renameStockOption(kind: 'unit' | 'category', previous: string, value: string) {
	const name = value.trim();
	if (!name) throw new Error('Enter a ' + kind + ' name.');
	commit(data => {
		const options = stockOptions(data, kind);
		if (!options.includes(previous)) throw new Error('Select an existing ' + kind + '.');
		if (options.some(option => option !== previous && option.toLowerCase() === name.toLowerCase())) {
			throw new Error('This ' + kind + ' already exists.');
		}
		const key = kind === 'unit' ? 'stockUnits' : 'stockCategories';
		data[key] = [...data[key].filter(option => option !== previous), name];
		for (const item of data.stock) {
			if (item[kind] === previous) item[kind] = name;
		}
		logOperation(data, 'Inventory', 'Renamed ' + kind, name, previous + ' → ' + name);
	});
}

function stockCategory(data: Operations, category: string) {
	const name = category.trim();
	return stockOptions(data, 'category').find(option => option.toLowerCase() === name.toLowerCase()) ?? name;
}

function validateStockDetails(details: StockDetails) {
	if ([details.unitCost, details.billingRate, details.capacity].some(value => value !== undefined && (!Number.isFinite(value) || value < 0))) {
		throw new Error('Enter nonnegative costs, billing rates, and capacity.');
	}
}

export function addStock(name: string, unit: string, quantity: number, minimum: number, category = '', details: StockDetails = {}) {
	validateStockDetails(details);
	if (!name.trim() || !unit.trim() || ![quantity, minimum].every((n) => Number.isFinite(n) && n >= 0)) throw new Error('Enter an item, unit, and valid stock amounts.');
	commit((data) => {
		if (data.stock.some((item) => item.name.toLowerCase() === name.trim().toLowerCase())) throw new Error('This item already exists. Use Add stock to increase its quantity.');
		const itemId = id();
		data.stock.push({ id: itemId, name: name.trim(), unit: unit.trim(), quantity, minimum, category: stockCategory(data, category), details });
		data.stockEntries.push({ id: id(), itemId, amount: quantity, reason: 'Opening stock', at: timestamp() });
		logOperation(data, 'Inventory', 'Created stock item', name.trim(), 'Opening stock: ' + quantity + ' ' + unit.trim() + ' · Reorder threshold: ' + minimum);
	});
}
export function editStockItem(itemId: string, name: string, unit: string, minimum: number, category: string, details?: StockDetails) {
	if (details) validateStockDetails(details);
	const trimmedName = name.trim();
	const trimmedUnit = unit.trim();
	if (!trimmedName || !trimmedUnit || !Number.isFinite(minimum) || minimum < 0) {
		throw new Error('Enter an item name, unit, and valid low stock threshold.');
	}
	commit(data => {
		const item = data.stock.find(item => item.id === itemId);
		if (!item) throw new Error('Stock item not found.');
		if (data.stock.some(other => other.id !== itemId && other.name.toLowerCase() === trimmedName.toLowerCase())) {
			throw new Error('An item with this name already exists.');
		}
		const updated = { name: trimmedName, unit: trimmedUnit, minimum, category: stockCategory(data, category) };
		const changes = (Object.keys(updated) as (keyof typeof updated)[]).flatMap(key =>
			(item[key] ?? '') === updated[key] ? [] : [key + ': ' + (item[key] ?? '—') + ' → ' + (updated[key] === '' ? '—' : updated[key])]);
		if (details) {
			const labels = { unitCost: 'Unit cost', capacity: 'Storage capacity', supplier: 'Supplier' } as const;
			for (const key of Object.keys(labels) as (keyof typeof labels)[]) {
				if ((item.details?.[key] ?? '') !== (details[key] ?? '')) changes.push(labels[key] + ': ' + (item.details?.[key] ?? '—') + ' → ' + (details[key] ?? '—'));
			}
		}
		Object.assign(item, updated);
		if (details) item.details = details;
		if (changes.length) logOperation(data, 'Inventory', 'Edited stock item', item.name, changes.join(' · '));
	});
}

export function adjustStock(itemId: string, amount: number, reason: string) {
	if (!Number.isFinite(amount) || !amount || !reason.trim()) throw new Error('Enter a stock adjustment and reason.');
	commit((data) => {
		const item = data.stock.find((item) => item.id === itemId);
		if (!item || item.quantity + amount < 0) throw new Error('Stock cannot go below zero.');
		const previous = item.quantity;
		item.quantity = Math.round((item.quantity + amount) * 1000) / 1000;
		data.stockEntries.push({ id: id(), itemId, amount, reason: reason.trim(), at: timestamp() });
		logOperation(data, 'Inventory', amount > 0 ? 'Stock in' : 'Stock out', item.name,
			previous + ' → ' + item.quantity + ' ' + item.unit + ' · ' + reason.trim());
	});
}
