<script lang="ts">
	import { resolve } from '$app/paths';
	import { tick } from 'svelte';
	import RewardReceipt from './RewardReceipt.svelte';
	import AdminBooking from './AdminBooking.svelte';
	import { money, serviceLabel } from './coating';
	import { audit, db } from './store.svelte';
	import { serviceOf, sizes } from './config';
	import { fmtDate, fmtSlot, today } from './dates';
	import { addStock, adjustStock, claimRewardReceipt, editRewardTier, grantPoints, ops, fanRanking, pointBalance } from './operations.svelte';

	let { tab }: { tab: string } = $props();
	let search = $state('');
	let memberId = $state('');
	let points = $state(1);
	let pointsDialog = $state<HTMLDialogElement>();
	let rewardDialog = $state<HTMLDialogElement>();
	let rewardIndex = $state(0);
	let rewardTitle = $state('');
	let rewardScope = $state('');
	let rewardCost = $state(1);
	let stockName = $state('');
	let stockSearch = $state('');
	let stockFilter = $state('all');
	let historyItem = $state('');
	const stockHealth = (quantity: number, minimum: number) => quantity === 0 ? 'out' : quantity <= minimum ? 'low' : 'healthy';
	const lowStock = $derived(ops.data.stock.filter(item => stockHealth(item.quantity, item.minimum) === 'low').length);
	const outOfStock = $derived(ops.data.stock.filter(item => item.quantity === 0).length);
	const visibleStock = $derived(ops.data.stock.filter(item =>
		item.name.toLowerCase().includes(stockSearch.trim().toLowerCase()) &&
		(stockFilter === 'all' || stockHealth(item.quantity, item.minimum) === stockFilter)
	));
	const stockHistory = $derived(ops.data.stockEntries.filter(entry => !historyItem || entry.itemId === historyItem).toReversed());
	let unit = $state('bottle');
	let quantity = $state(0);
	let minimum = $state(0);
	let stockId = $state('');
	let adjustment = $state(1);
	let stockReason = $state('');
	let stockDialog = $state<HTMLDialogElement>();
	let stockMode = $state<'add' | 'use'>('add');
	const selectedStock = $derived(ops.data.stock.find((item) => item.id === stockId));
	let from = $state(today().slice(0, 7) + '-01');
	let to = $state(today());
	let notice = $state('');
	let error = $state('');
	let statusFilter = $state('all');
	const matchingBookings = $derived(db.bookings.filter((b) => (statusFilter === 'all' || b.status === statusFilter) && [b.id, b.name, b.phone, b.bike, b.plateNumber ?? ''].join(' ').toLowerCase().includes(search.toLowerCase())).toSorted((a, b) => (b.date + b.slot).localeCompare(a.date + a.slot)));
	const customers = $derived(ops.data.members.filter((member) => (member.name + member.phone + member.id).toLowerCase().includes(search.toLowerCase())));
	const selected = $derived(ops.data.members.find((member) => member.id === memberId));
	const filteredBookings = $derived(db.bookings.filter((booking) => booking.date >= from && booking.date <= to));
	const completed = $derived(db.bookings.filter(b => { const date = b.completedAt ? new Intl.DateTimeFormat('en-CA', {timeZone:'Asia/Manila'}).format(new Date(b.completedAt)) : b.date; return b.status === 'done' && date >= from && date <= to; }));
	const valued = $derived(completed.filter(b => b.estimate));
	const income = $derived(valued.reduce((sum, b) => sum + b.estimate!.total, 0));
	const ranking = $derived(fanRanking());
	const rewardProgram = $derived(ops.data.rewardProgram);

	async function openPoints(fanId: string) {
		memberId = fanId;
		points = 1;
		error = '';
		notice = '';
		await tick();
		pointsDialog?.showModal();
	}
	async function openReward(index: number) {
		const reward = rewardProgram[index];
		rewardIndex = index;
		rewardTitle = reward.name;
		rewardScope = reward.scope ?? '';
		rewardCost = reward.points;
		error = '';
		await tick();
		rewardDialog?.showModal();
	}
	async function openStock(itemId = '', mode: 'add' | 'use' = 'add') {
		stockId = itemId;
		stockMode = mode;
		adjustment = 1;
		stockReason = '';
		error = '';
		await tick();
		stockDialog?.showModal();
	}

	function perform(action: () => void, message: string) {
		error = '';
		notice = '';
		try { action(); notice = message; if (['HERCO Points', 'Inventory', 'Customers'].includes(tab)) audit(message); }
		catch (e) { error = (e as Error).message; }
	}
	function exportBookings() {
		const rows = [
			['Reference', 'Date', 'Time', 'Name', 'Phone', 'Bike model', 'Plate', 'Service', 'Status'],
			...filteredBookings.map((b) => [b.id, b.date, fmtSlot(b.slot), b.name, b.phone, b.bike, b.plateNumber ?? '', b.selection ? serviceLabel(b.selection) : serviceOf(b.serviceId).name, b.status])
		];
		const csv = rows.map((row) => row.map((value) => {
			const safe = /^[=+\-@\t\r]/.test(value) ? "'" + value : value;
			return '"' + safe.replaceAll('"', '""') + '"';
		}).join(',')).join('\r\n');
		const url = URL.createObjectURL(new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8' }));
		const link = document.createElement('a');
		link.href = url;
		link.download = `herco-bookings-${from}-${to}.csv`;
		link.click();
		audit('Exported booking report');
		setTimeout(() => URL.revokeObjectURL(url), 1000);
	}
</script>

<div class="stack">
	{#if error}<p class="error" role="alert">{error}</p>{/if}
	{#if notice}<p class="success" role="status">{notice}</p>{/if}

	{#if tab === 'Overview'}
		<div class="cols">
			<div class="card stack"><span class="muted">Awaiting confirmation</span><b class="metric">{db.bookings.filter((b) => b.status === 'pending').length}</b></div>
			<div class="card stack"><span class="muted">Confirmed bookings</span><b class="metric">{db.bookings.filter((b) => b.status === 'confirmed').length}</b></div>
			<div class="card stack"><span class="muted">HERCO Points fans</span><b class="metric">{ops.data.members.length}</b></div>
			<div class="card stack"><span class="muted">Items low on stock</span><b class="metric">{ops.data.stock.filter((item) => item.quantity <= item.minimum).length}</b></div>
		</div>
		<div class="card stack">
			<h3>Upcoming visits</h3>
			{#each db.bookings.filter((b) => b.date >= today() && ['pending', 'confirmed'].includes(b.status)).toSorted((a, b) => (a.date + a.slot).localeCompare(b.date + b.slot)).slice(0, 6) as b (b.id)}
				<div class="ledger"><div><b>{b.name || 'Unnamed test booking'}</b><p class="muted small">{serviceOf(b.serviceId).name} · {b.bike || 'Bike not provided'}</p></div><span>{fmtDate(b.date, { month: 'short', day: 'numeric' })} · {fmtSlot(b.slot)}</span></div>
			{:else}<p class="muted">No upcoming visits.</p>{/each}
		</div>
		<div class="card stack"><h3>HERCO Points</h3><p class="muted">{ops.data.members.length} fan accounts. Search for a fan in HERCO Points to add points and view the ranking.</p><a href={resolve('/points')}>Open customer points page ↗</a></div>
	{:else if tab === 'Booking history'}
		<div class="cols">
			<label>Search bookings<input type="search" bind:value={search} placeholder="Name, reference, mobile, bike or plate" /></label>
			<label>Status<select bind:value={statusFilter}><option value="all">All bookings</option><option value="pending">Pending</option><option value="confirmed">Confirmed</option><option value="done">Completed</option><option value="cancelled">Cancelled</option></select></label>
		</div>
		{#each matchingBookings as booking (booking.id)}
			<details class="card booking-record">
				<summary>
					<span class="record-heading"><strong>{booking.name || 'Unnamed test booking'}</strong><span class="muted small">{booking.id} · {fmtDate(booking.date, { month: 'short', day: 'numeric', year: 'numeric' })} · {fmtSlot(booking.slot)}</span></span>
					<span class="record-status"><span class="badge" data-status={booking.status}>{booking.status === 'done' ? 'Completed' : booking.status}</span><span class="expand-icon" aria-hidden="true">⌄</span></span>
				</summary>
				<div class="record-body stack">
				<div class="cols">
					<div class="stack">
						<h3>Customer &amp; motorcycle</h3>
						<dl class="record-details">
							<div><dt>Customer</dt><dd>{booking.name || 'Not provided'}</dd></div>
							<div><dt>Mobile</dt><dd>{#if booking.phone}<a href={`tel:${booking.phone}`}>{booking.phone}</a>{:else}Not provided{/if}</dd></div>
							<div><dt>Email</dt><dd>{#if booking.email}<a href={`mailto:${booking.email}`}>{booking.email}</a>{:else}Not provided{/if}</dd></div>
							<div><dt>Bike model</dt><dd>{booking.bike || 'Not provided'}</dd></div>
							<div><dt>Plate number</dt><dd>{booking.plateNumber || 'Not provided'}</dd></div>
							{#if booking.size}<div><dt>Bike category</dt><dd>{sizes[booking.size]}</dd></div>{/if}
						</dl>
					</div>
					<div class="stack">
						<h3>Service &amp; visit</h3>
						<dl class="record-details">
							<div><dt>Service</dt><dd>{booking.selection ? serviceLabel(booking.selection) : serviceOf(booking.serviceId).name}</dd></div>
							{#if booking.finish}<div><dt>Preferred finish</dt><dd>{booking.finish}</dd></div>{/if}
							<div><dt>Visit</dt><dd>{fmtDate(booking.date)} · {fmtSlot(booking.slot)}</dd></div>
						</dl>
					</div>
				</div>
				<div class="stack"><h3>Notes for the shop</h3><p class="booking-notes">{booking.notes || 'No notes provided.'}</p></div>
				<AdminBooking {booking} />
				</div>
			</details>
		{:else}<p class="muted">No matching bookings.</p>{/each}
	{:else if tab === 'Customers'}
		<h3>Customers</h3>
		<label>Search customers<input type="search" bind:value={search} placeholder="Customer name or mobile number" /></label>
		{#each customers as customer (customer.id)}
			<details class="card">
				<summary><b>{customer.name}</b> <span class="muted small">· {customer.demoFan ? 'Sample fan account' : 'Fan account'}</span></summary>
				<div class="stack customer-profile">
					<p>Mobile {customer.phone || 'Not provided'}</p>
					<p class="muted small">Account {customer.id}</p>
					<h3>Booking history</h3>
					{#each db.bookings.filter((b) => b.customerId === customer.id || (!b.customerId && ((customer.phone && b.phone === customer.phone) || b.name.trim().toLowerCase() === customer.name.toLowerCase()))).toSorted((a, b) => b.date.localeCompare(a.date)) as b (b.id)}
						<div class="ledger"><div><b>{serviceOf(b.serviceId).name}</b><p class="muted small">{b.bike} · {b.id}</p></div><span>{fmtDate(b.date, { month: 'short', day: 'numeric' })} · {fmtSlot(b.slot)} · {b.status}</span></div>
					{:else}<p class="muted">No linked bookings yet.</p>{/each}
				</div>
			</details>
		{:else}<p class="muted">No matching customers.</p>{/each}
	{:else if tab === 'HERCO Points'}
		<h3>HERCO Points ranking</h3>
		<p class="muted small">Search fan accounts, add HERCO Points and view their ranking. Sample accounts are fictional.</p>
		<label>Find a fan<input type="search" bind:value={search} placeholder="Fan name or account ID" /></label>
		<div class="card leaderboard">
			{#each ranking as fan, index (fan.id)}
				{#if (fan.name + fan.id).toLowerCase().includes(search.toLowerCase())}
					<div class="rank-row">
						<b class="rank-number" class:podium={index < 3}>#{index + 1}</b>
						<div class="rank-fan"><b>{fan.name}</b><span class="muted small">{fan.demoFan ? 'Sample fan account' : 'Fan account'}</span></div>
						<strong class="rank-points">{pointBalance(fan.id)} <span class="small muted">points</span></strong>
						<button class="btn sm ghost" onclick={() => openPoints(fan.id)}>Add HERCO Points</button>
					</div>
				{/if}
			{/each}
			{#if !ranking.some((fan) => (fan.name + fan.id).toLowerCase().includes(search.toLowerCase()))}<p class="muted">No fans found.</p>{/if}
		</div>
		<dialog bind:this={pointsDialog} aria-labelledby="points-dialog-title">
			{#if selected}
			<div class="stack">
				<div class="dialog-heading row"><h3 id="points-dialog-title">Add HERCO Points</h3><button class="close-dialog" aria-label="Close points popup" onclick={() => pointsDialog?.close()}>×</button></div>
				<h3>{selected.name} · {pointBalance(selected.id)} points</h3>
				<p class="small muted">Account {selected.id}</p>
				<p class="muted small">Points are credited to the selected fan account.</p>
				{#if error}<p class="error" role="alert">{error}</p>{/if}
				<form class="stack" onsubmit={(e) => { e.preventDefault(); perform(() => { grantPoints(selected.id, points); pointsDialog?.close(); }, 'HERCO Points added.'); }}>
					<label>Points to add<input type="number" min="1" step="1" required bind:value={points} /></label>
					<div class="row"><button class="btn sm">Add HERCO Points</button><button type="button" class="btn sm ghost" onclick={() => pointsDialog?.close()}>Cancel</button></div>
				</form>
				<h3>Points history</h3>
				{#each ops.data.points.filter((entry) => entry.memberId === selected.id).toReversed() as entry (entry.id)}
					<div class="ledger"><div>{entry.reason}<p class="muted small">{new Date(entry.at).toLocaleString('en-PH', { timeZone: 'Asia/Manila', hour12: true })}</p></div><b>{entry.amount > 0 ? '+' : ''}{entry.amount}</b></div>
				{:else}<p class="muted">No points activity.</p>{/each}
			</div>
			{/if}
		</dialog>
		<details class="card"><summary>HERCO Rewards Program</summary>
			{#each rewardProgram as reward, index (index)}
				<div class="ledger"><b>{reward.points.toLocaleString('en-PH')} points</b><span>{reward.name}{reward.scope ? ' · ' + reward.scope : ''}</span><button class="btn sm ghost" onclick={() => openReward(index)}>Edit reward</button></div>
			{/each}
		</details>
		<dialog bind:this={rewardDialog} aria-labelledby="reward-dialog-title">
			<form class="stack" onsubmit={(e) => { e.preventDefault(); perform(() => { editRewardTier(rewardIndex, { name: rewardTitle, scope: rewardScope, points: rewardCost }); rewardDialog?.close(); }, 'Reward updated.'); }}>
				<div class="dialog-heading row"><h3 id="reward-dialog-title">Edit reward</h3><button type="button" class="close-dialog" aria-label="Close reward popup" onclick={() => rewardDialog?.close()}>×</button></div>
				{#if error}<p class="error" role="alert">{error}</p>{/if}
				<label>Reward name<input required bind:value={rewardTitle} /></label>
				<label>Scope (optional)<input bind:value={rewardScope} placeholder="e.g. Small parts" /></label>
				<label>Points required<input type="number" min="1" step="1" required bind:value={rewardCost} /></label>
				<div class="row"><button class="btn sm">Save reward</button><button type="button" class="btn sm ghost" onclick={() => rewardDialog?.close()}>Cancel</button></div>
			</form>
		</dialog>
		<div class="card stack">
			<h3>Redemption and claim history</h3>
			{#each ops.data.rewardReceipts.toReversed().filter((receipt) => (receipt.memberName + receipt.reference).toLowerCase().includes(search.toLowerCase())) as receipt (receipt.id)}
				<details>
					<summary>{receipt.memberName} · {receipt.reward} · {receipt.status === 'claimed' ? 'Claimed' : 'Awaiting claim'}</summary>
					<div class="stack">
						<RewardReceipt {receipt} />
						{#if receipt.status === 'issued'}<div><button class="btn sm complete-action" onclick={() => perform(() => claimRewardReceipt(receipt.id), 'Reward AR marked as claimed.')}>Mark as claimed</button></div>{/if}
					</div>
				</details>
			{:else}<p class="muted">No matching reward redemptions.</p>{/each}
		</div>
	{:else if tab === 'Inventory'}
		<div class="cols" aria-label="Inventory summary">
			<button type="button" class="opt" class:on={stockFilter === 'all'} aria-pressed={stockFilter === 'all'} onclick={() => stockFilter = 'all'}><b>{ops.data.stock.length}</b> All items</button>
			<button type="button" class="opt" class:on={stockFilter === 'low'} aria-pressed={stockFilter === 'low'} onclick={() => stockFilter = 'low'}><b>{lowStock}</b> Low stock</button>
			<button type="button" class="opt" class:on={stockFilter === 'out'} aria-pressed={stockFilter === 'out'} onclick={() => stockFilter = 'out'}><b>{outOfStock}</b> Out of stock</button>
		</div>
		<div class="cols">
			<form class="card stack" onsubmit={(e) => { e.preventDefault(); perform(() => { addStock(stockName, unit, quantity, minimum); stockName = ''; }, 'Stock item added.'); }}>
				<h3>Create new inventory item</h3>
				<label>Item name<input bind:value={stockName} placeholder="e.g. Ceramic coating" required /></label>
				<div class="cols"><label>Unit<input bind:value={unit} required /></label><label>Opening stock<input type="number" min="0" step="0.001" bind:value={quantity} required /></label><label>Low stock threshold<input type="number" min="0" step="0.001" bind:value={minimum} required /></label></div>
				<button class="btn sm">Add item</button>
			</form>
			<div class="card stack">
				<h3>Update existing stock</h3>
				<p class="muted">Add a delivery to an item’s current quantity, or record supplies used during a service.</p>
				<div class="row"><button class="btn sm" onclick={() => openStock()}>Add stock</button><button class="btn sm ghost" onclick={() => openStock('', 'use')}>Record usage</button></div>
				<p class="small muted">Every update is saved in stock history.</p>
			</div>
		</div>
		<div class="card stack">
			<h3>Stock on hand</h3>
			<label>Search supplies<input type="search" bind:value={stockSearch} placeholder="e.g. Ceramic coating" /></label>
			{#each visibleStock as item (item.id)}
				{@const health = stockHealth(item.quantity, item.minimum)}
				<div class="ledger">
					<div><b>{item.name}</b><p class="small muted">{item.quantity} {item.unit} on hand · Reorder at {item.minimum}</p></div>
					<div class="row">
						<span class="badge" data-status={health === 'out' ? 'cancelled' : health === 'low' ? 'pending' : 'done'}>{health === 'out' ? 'Out of stock' : health === 'low' ? 'Low stock' : 'In stock'}</span>
						<button class="btn sm ghost" aria-label={'Stock in for ' + item.name} onclick={() => openStock(item.id)}>Stock in</button>
						<button class="btn sm ghost" aria-label={'Stock out for ' + item.name} disabled={!item.quantity} onclick={() => openStock(item.id, 'use')}>Stock out</button>
					</div>
				</div>
			{:else}<p class="muted">No supplies match this view.</p>{/each}
		</div>
		<dialog bind:this={stockDialog} aria-labelledby="stock-dialog-title">
			<form class="stack" onsubmit={(e) => {
				e.preventDefault();
				perform(() => {
					if (!Number.isFinite(adjustment) || adjustment <= 0) throw new Error('Enter a positive quantity.');
					adjustStock(stockId, stockMode === 'add' ? adjustment : -adjustment, stockReason.trim() || (stockMode === 'add' ? 'Stock received' : 'Used for service'));
					stockDialog?.close();
				}, stockMode === 'add' ? 'Stock added to the existing item.' : 'Usage recorded.');
			}}>
				<div class="dialog-heading row"><h3 id="stock-dialog-title">{stockMode === 'add' ? 'Add stock' : 'Record usage'}</h3><button type="button" class="close-dialog" aria-label="Close stock popup" onclick={() => stockDialog?.close()}>×</button></div>
				{#if error}<p class="error" role="alert">{error}</p>{/if}
				<label>Item<select bind:value={stockId} required><option value="">Select item</option>{#each ops.data.stock as item (item.id)}<option value={item.id}>{item.name}</option>{/each}</select></label>
				<label>Update type<select bind:value={stockMode}><option value="add">Add stock</option><option value="use">Record usage</option></select></label>
				{#if selectedStock}<p>Current stock <b>{selectedStock.quantity} {selectedStock.unit}</b></p>{/if}
				<label>Quantity {selectedStock ? '(' + selectedStock.unit + ')' : ''}<input type="number" min="0.001" step="0.001" bind:value={adjustment} required /></label>
				{#if selectedStock && Number.isFinite(adjustment)}
					<p>Stock after update <b>{Math.round((selectedStock.quantity + (stockMode === 'add' ? adjustment : -adjustment)) * 1000) / 1000} {selectedStock.unit}</b></p>
				{/if}
				<label>Note (optional)<input bind:value={stockReason} placeholder={stockMode === 'add' ? 'e.g. Supplier delivery' : 'e.g. Ceramic coating service'} /></label>
				<div class="row"><button class="btn sm">{stockMode === 'add' ? 'Add stock' : 'Save usage'}</button><button type="button" class="btn sm ghost" onclick={() => stockDialog?.close()}>Cancel</button></div>
			</form>
		</dialog>
		<details class="card"><summary>Stock history</summary>
			<label>Filter stock history<select bind:value={historyItem}><option value="">All items</option>{#each ops.data.stock as item (item.id)}<option value={item.id}>{item.name}</option>{/each}</select></label>
			{#each stockHistory as entry (entry.id)}<div class="ledger"><div>{ops.data.stock.find((item) => item.id === entry.itemId)?.name}<p class="small muted">{entry.reason} · {new Date(entry.at).toLocaleString('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short', hour12: true })}</p></div><b>{entry.amount > 0 ? '+' : ''}{entry.amount}</b></div>{:else}<p class="muted">No stock movements for this view.</p>{/each}
		</details>
	{:else if tab === 'Reports'}
		<div class="row"><label>From<input type="date" bind:value={from} max={to} /></label><label>To<input type="date" bind:value={to} min={from} /></label><button class="btn sm ghost" onclick={exportBookings}>Export bookings CSV</button></div>
		<div class="cols">
			<div class="card stack"><span class="muted">Bookings in period</span><b class="metric">{filteredBookings.length}</b></div>
			<div class="card stack"><span class="muted">Completed services</span><b class="metric">{completed.length}</b></div>
			<div class="card stack"><span class="muted">Cancelled bookings</span><b class="metric">{filteredBookings.filter((b) => b.status === 'cancelled').length}</b></div>
			<div class="card stack"><span class="muted">Estimated income from completed services</span><b class="metric">{money(income)}</b></div>
			<div class="card stack"><span class="muted">Average completed service value</span><b class="metric">{money(valued.length ? income / valued.length : 0)}</b></div>
			<div class="card stack"><span class="muted">Pending and confirmed bookings</span><b class="metric">{filteredBookings.filter(b => b.status === 'pending' || b.status === 'confirmed').length}</b></div>
			<div class="card stack"><span class="muted">Walk-in bookings</span><b class="metric">{filteredBookings.filter(b => b.walkIn).length}</b></div>
			<div class="card stack"><span class="muted">Promo discounts on completed work</span><b class="metric">{money(valued.reduce((sum, b) => sum + b.estimate!.discount, 0))}</b></div>
		</div>
		<p class="small muted">Philippine time. Income is based on saved service estimates for completed work. Older jobs without an estimate are excluded from value totals.</p>
	{/if}
</div>

<style>
	dialog {
		width: min(560px, calc(100vw - 32px));
		max-height: calc(100dvh - 48px);
		padding: 24px;
		overflow-y: auto;
		border: 1px solid var(--line);
		border-radius: 12px;
		background: var(--panel);
		color: var(--text);
	}
	dialog::backdrop { background: rgb(0 0 0 / 75%); }
	.dialog-heading { justify-content: space-between; }
	.close-dialog { width: 40px; height: 40px; border: 1px solid var(--line); border-radius: 50%; background: var(--panel-2); color: var(--text); font-size: 1.5rem; cursor: pointer; }
	.customer-profile { padding-top: 18px; }
	.rank-row { display: flex; flex-wrap: wrap; align-items: center; gap: 16px; padding-block: 18px; border-bottom: 1px solid var(--line); }
	.rank-number { font: italic 800 1.8rem var(--display); color: var(--muted); min-width: 40px; }
	.podium { color: var(--accent); }
	.rank-fan { display: grid; flex: 1 1 160px; gap: 4px; }
	.rank-points { font-size: 1.3rem; min-width: 95px; }
	.rank-points span { display: block; }
	.booking-record { padding: 0; }
	.booking-record > summary { display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 18px; }
	.booking-record > summary::-webkit-details-marker { display: none; }
	.record-heading { display: grid; gap: 6px; }
	.record-heading strong { font: italic 800 1.6rem var(--display); text-transform: uppercase; }
	.record-status { display: flex; align-items: center; gap: 12px; }
	.expand-icon { color: var(--accent); font-size: 1.5rem; }
	.booking-record[open] .expand-icon { transform: rotate(180deg); }
	.record-body { padding: 18px; border-top: 1px solid var(--line); }
	.record-details { display: grid; gap: 12px; margin: 0; }
	.record-details dt { color: var(--muted); font-size: 0.85rem; }
	.record-details dd { margin: 0; overflow-wrap: anywhere; }
	.booking-notes { white-space: pre-wrap; overflow-wrap: anywhere; }
	.metric { font: italic 800 2.4rem var(--display); }
	.ledger { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; padding-block: 12px; border-bottom: 1px solid var(--line); }
	.success { color: var(--ok); }
	summary { cursor: pointer; }
	.cols { grid-template-columns: repeat(auto-fit, minmax(min(100%, 230px), 1fr)); }
</style>
