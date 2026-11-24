<script lang="ts">
	import ActionIcon from '#lib/shared/ActionIcon.svelte';
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
	import { adminPath } from './adminNavigation';
	import { tick } from 'svelte';
	import RewardReceipt from '../shared/RewardReceipt.svelte';
	import { approveRewardReceipt, correctPoints, rewardStatus, type Member } from './operations.svelte';
	import AdminBooking from './AdminBooking.svelte';
	import DemoBookingSheet from './DemoBookingSheet.svelte';
	import Pager from '../shared/Pager.svelte';
	import { pageCount } from '../shared/paging';
	import RecordFilterBar from '../shared/RecordFilterBar.svelte';
	import RecordsEmpty from '../shared/RecordsEmpty.svelte';
	import StatusTiles from '../shared/StatusTiles.svelte';
	import { rangeIssue, statusLabels, type RecordFilters } from '../shared/records-ui';
	import { canPerform } from './staffAccess.svelte.ts';
	import { serviceLabel } from '../shared/coating';
	import type { StockDetails } from './operations.svelte';
	import { bookingStatusLabels, db, type Booking } from './store.svelte';
	import { serviceOf } from '../shared/config';
	import { fmtDate, fmtSlot, today } from '../shared/dates';
	import { addStock, addStockOption, adjustStock, claimRewardReceipt, editRewardTier, editStockItem, grantPoints, ops, fanRanking, pointBalance, renameStockOption, stockOptions } from './operations.svelte';

	let { tab }: { tab: string } = $props();
	const canManageInventory = $derived(canPerform('manageInventory'));
	const showRedemptions = $derived(page.url.searchParams.get('section') === 'Redemptions');
	const pageSize = 10;
	let search = $state('');
	let memberId = $state('');
	let points = $state(1);
	let pointsDialog = $state<HTMLDialogElement>();
	let rewardDialog = $state<HTMLDialogElement>();
	let rewardIndex = $state(0);
	let correctingPoints = $state(false);
	let correctionReason = $state('');
	let rewardTitle = $state('');
	let rewardScope = $state('');
	let rewardCost = $state(1);
	let stockName = $state('');
	let stockSearch = $state('');
	let newStockDetails = $state<StockDetails>({});
	let editStockDetails = $state<StockDetails>({});
	let stockFilter = $state('all');
	let categoryFilter = $state('');
	let newItemCategory = $state('');
	let editItemDialog = $state<HTMLDialogElement>();
	let itemDraft = $state({ id: '', name: '', unit: '', minimum: 0, category: '' });
	const categories = $derived(stockOptions(ops.data, 'category'));
	const units = $derived(stockOptions(ops.data, 'unit'));
	let optionDialog = $state<HTMLDialogElement>();
	let optionKind = $state<'unit' | 'category'>('unit');
	let optionName = $state('');
	let addingOptionToNewItem = $state(false);
	let renamingOption = $state(false);
	let previousOption = $state('');
	const existingOptions = $derived(optionKind === 'unit' ? units : categories);

	function resetStockOption() {
		error = '';
		previousOption = '';
		optionName = '';
	}

	function openInventoryOptions(kind: 'unit' | 'category', forNewItem = false) {
		optionKind = kind;
		renamingOption = false;
		addingOptionToNewItem = forNewItem;
		resetStockOption();
		optionDialog?.showModal();
	}
	let historyItem = $state('');
	let stockPage = $state(1);
	let historyPage = $state(1);
	const stockHealth = (quantity: number, minimum: number) => quantity === 0 ? 'out' : quantity <= minimum ? 'low' : 'healthy';
	const lowStock = $derived(ops.data.stock.filter(item => stockHealth(item.quantity, item.minimum) === 'low').length);
	const outOfStock = $derived(ops.data.stock.filter(item => item.quantity === 0).length);
	const inStock = $derived(ops.data.stock.length - lowStock - outOfStock);
	const visibleStock = $derived(ops.data.stock.filter(item =>
		[item.name, item.category, item.details?.location].some(value => value?.toLowerCase().includes(stockSearch.trim().toLowerCase())) &&
		(!categoryFilter || categoryFilter === (item.category ? 'category:' + item.category : 'uncategorized')) &&
		(stockFilter === 'all' || stockHealth(item.quantity, item.minimum) === stockFilter)
	));
	const stockHistory = $derived(ops.data.stockEntries.filter(entry => !historyItem || entry.itemId === historyItem).toReversed());
	const stockPages = $derived(Math.max(1, Math.ceil(visibleStock.length / pageSize)));
	const historyPages = $derived(Math.max(1, Math.ceil(stockHistory.length / pageSize)));
	const currentStockPage = $derived(Math.min(stockPage, stockPages));
	const currentHistoryPage = $derived(Math.min(historyPage, historyPages));
	let unit = $state('bottle');
	let quantity = $state(0);
	let minimum = $state(0);
	let stockId = $state('');
	let adjustment = $state(1);
	let stockReason = $state('');
	let stockDialog = $state<HTMLDialogElement>();
	let newItemDialog = $state<HTMLDialogElement>();
	let stockMode = $state<'add' | 'use'>('add');
	const selectedStock = $derived(ops.data.stock.find((item) => item.id === stockId));
	let notice = $state('');
	let error = $state('');
		const bookingPeriods = [
			{ value: 'today', label: 'Today' }, { value: 'month', label: 'This month' },
			{ value: 'date', label: 'Specific date' }, { value: 'custom', label: 'Custom range' },
			{ value: 'all', label: 'All dates' }
		];
		const shopToday = today();
		const bookingDefaults = (): RecordFilters => ({ preset: 'today', from: shopToday.slice(0, 7) + '-01', through: shopToday, exact: shopToday, search: '', status: 'all', source: 'all' });
		let filters = $state<RecordFilters>(bookingDefaults());
		let bookingPage = $state(1);
		let detail = $state<Booking>();
		const validBookingPeriod = $derived(!rangeIssue(filters));
		const bookingQuery = $derived(filters.search.trim().toLowerCase());
		const periodBookings = $derived(db.bookings.filter(b => validBookingPeriod &&
			(filters.preset === 'all' ||
				(filters.preset === 'today' && b.date === shopToday) ||
				(filters.preset === 'month' && b.date.slice(0, 7) === shopToday.slice(0, 7)) ||
				(filters.preset === 'date' && b.date === filters.exact) ||
				(filters.preset === 'custom' && b.date >= filters.from && b.date <= filters.through)) &&
			(filters.source === 'all' || Boolean(b.walkIn) === (filters.source === 'walk-in')) &&
			[b.id, b.name, b.phone, b.bike, b.plateNumber ?? ''].join(' ').toLowerCase().includes(bookingQuery)));
		const bookingMetrics = $derived([
			{ value: 'all', label: 'All bookings', count: periodBookings.length },
			...Object.entries(statusLabels).map(([value, label]) => ({ value, label, count: periodBookings.filter(b => b.status === value).length }))
		]);
		const matchingBookings = $derived(periodBookings.filter(b => filters.status === 'all' || b.status === filters.status)
			.toSorted((a, b) => (b.date + b.slot).localeCompare(a.date + a.slot) || a.id.localeCompare(b.id)));
		const bookingPages = $derived(pageCount(matchingBookings.length, pageSize));
		const currentBookingPage = $derived(Math.min(bookingPage, bookingPages));
		const bookingOffset = $derived((currentBookingPage - 1) * pageSize);

		function resetBookingFilters() {
			filters = bookingDefaults();
			bookingPage = 1;
		}
	const customers = $derived(ops.data.members.filter(member => matchesFan(member, fanQuery)));
	let customerPage = $state(1);
	const customerPages = $derived(Math.max(1, Math.ceil(customers.length / pageSize)));
	const currentCustomerPage = $derived(Math.min(customerPage, customerPages));
	const customerOffset = $derived((currentCustomerPage - 1) * pageSize);
	const selected = $derived(ops.data.members.find((member) => member.id === memberId));
	const ranking = $derived(fanRanking());
	const fanQuery = $derived(search.trim().toLowerCase());
	let pointsSearch = $state('');
	const pointsQuery = $derived(pointsSearch.trim().toLowerCase());
	function matchesFan(fan: Member, query: string) {
		const digits = query.replace(/\D/g, '');
		return [fan.name, fan.email ?? '', fan.id, fan.phone].some(value => value.toLowerCase().includes(query)) ||
			(Boolean(digits) && /^[+\d\s().-]+$/.test(query) && fan.phone.replace(/\D/g, '').includes(digits));
	}
	const matchingFans = $derived(ranking.map((fan, index) => ({ fan, rank: index + 1 })).filter(({ fan }) => matchesFan(fan, fanQuery)));
	let leaderboardSort = $state('highest');
	let leaderboardPage = $state(1);
	const sortedFans = $derived(leaderboardSort === 'name'
		? matchingFans.toSorted((a, b) => a.fan.name.localeCompare(b.fan.name) || a.rank - b.rank)
		: leaderboardSort === 'lowest'
			? matchingFans.toSorted((a, b) => pointBalance(a.fan.id) - pointBalance(b.fan.id) || a.rank - b.rank)
			: matchingFans);
	const leaderboardPages = $derived(Math.max(1, Math.ceil(sortedFans.length / pageSize)));
	const currentLeaderboardPage = $derived(Math.min(leaderboardPage, leaderboardPages));
	const redemptionStatuses = [
		{ value: 'pending', label: 'Pending for approval', tone: 'pending' },
		{ value: 'approved', label: 'Approved · awaiting claim', tone: 'confirmed' },
		{ value: 'claimed', label: 'Claimed', tone: 'done' }
	] as const;
	let redemptionFilter = $state('pending');
	let redemptionSearch = $state('');
	let redemptionSort = $state('oldest');
	let redemptionPage = $state(1);
	const redemptions = $derived(ops.data.rewardReceipts.map(receipt => {
		const status = receipt.status === 'issued' ? 'approved' : receipt.status;
		return { receipt, status };
	}));
	const redemptionCounts = $derived({
		pending: redemptions.filter(row => row.status === 'pending').length,
		approved: redemptions.filter(row => row.status === 'approved').length,
		claimed: redemptions.filter(row => row.status === 'claimed').length
	});
	const redemptionQuery = $derived(redemptionSearch.trim().toLowerCase());
	const redemptionMembers = $derived(new Set(ops.data.members.filter(fan => matchesFan(fan, redemptionQuery)).map(fan => fan.id)));
	const visibleRedemptions = $derived(redemptions
		.filter(({ receipt, status }) =>
			(redemptionFilter === 'all' || status === redemptionFilter) &&
			(!redemptionQuery || redemptionMembers.has(receipt.memberId) ||
				[receipt.memberName, receipt.reference].some(value => value.toLowerCase().includes(redemptionQuery))))
		.sort((a, b) => redemptionSort === 'oldest'
			? Date.parse(a.receipt.at) - Date.parse(b.receipt.at)
			: Date.parse(b.receipt.at) - Date.parse(a.receipt.at)));
	const redemptionPages = $derived(Math.max(1, Math.ceil(visibleRedemptions.length / pageSize)));
	const currentRedemptionPage = $derived(Math.min(redemptionPage, redemptionPages));
	const redemptionDate = new Intl.DateTimeFormat('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short' });
	const pointsMatches = $derived(pointsQuery ? ranking.filter(fan => matchesFan(fan, pointsQuery)) : []);
	const rewardProgram = $derived(ops.data.rewardProgram);

	async function openPoints() {
		memberId = '';
		pointsSearch = search;
		points = 1;
		correctingPoints = false;
		correctionReason = '';
		error = '';
		notice = '';
		await tick();
		pointsDialog?.showModal();
	}
	function selectReward(index: number) {
		const reward = rewardProgram[index];
		rewardIndex = index;
		rewardTitle = reward.name;
		rewardScope = reward.scope ?? '';
		rewardCost = reward.points;
		error = '';
	}
	async function openReward() {
		selectReward(0);
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
		try { action(); notice = message; }
		catch (e) { error = (e as Error).message; }
	}
</script>

<div class="stack">
	{#if error}<p class="error" role="alert">{error}</p>{/if}
	{#if notice}<p class="success" role="status">{notice}</p>{/if}

	{#if tab === 'Booking history'}
		<section class="stack" aria-label="Booking history">
			<StatusTiles tiles={bookingMetrics} selected={filters.status} onpick={(value) => { filters.status = value; bookingPage = 1; }} />
			<div class="card"><RecordFilterBar bind:filters periods={bookingPeriods} showStatus={false} onchange={() => bookingPage = 1} onreset={resetBookingFilters} /></div>
			<div class="row list-head"><h2>Bookings</h2><p class="small muted" role="status">{matchingBookings.length} {matchingBookings.length === 1 ? 'booking' : 'bookings'}</p></div>
			<div class="stack">
				{#each matchingBookings.slice(bookingOffset, bookingOffset + pageSize) as booking (booking.id)}<article class="card"><AdminBooking {booking} when={fmtDate(booking.date, { month: 'short', day: 'numeric' }) + ', ' + fmtSlot(booking.slot)} onDetails={() => detail = booking} /></article>{:else}
					<RecordsEmpty title="No bookings found" text="Try another date, status or search to find your bookings." action="Reset filters" onaction={resetBookingFilters} />
				{/each}
			</div>
			<Pager page={currentBookingPage} pages={bookingPages} label="Booking history" onchange={(next) => bookingPage = next} />
		</section>
	{:else if tab === 'Customers'}
		<div class="card customer-total"><span class="muted small">Total accounts</span><b>{ops.data.members.length}</b></div>
		<label>Search customers<input type="search" bind:value={search} oninput={() => customerPage = 1} placeholder="Name, email, mobile number or account ID" /></label>
		{#each customers.slice(customerOffset, customerOffset + pageSize) as customer (customer.id)}
			{@const bookings = db.bookings.filter(b => b.accountId === customer.id || b.customerId === customer.id || (!b.accountId && !b.customerId && ((customer.phone && b.phone === customer.phone) || b.name.trim().toLowerCase() === customer.name.toLowerCase()))).toSorted((a, b) => (b.date + b.slot).localeCompare(a.date + a.slot))}
			<details class="card customer-record">
				<summary><span><b>{customer.name}</b> <span class="muted small">{customer.id}</span></span><span class="customer-record-meta">{bookings[0]?.bike ?? ''} <span class="badge">{bookings.length} {bookings.length === 1 ? 'booking' : 'bookings'}</span></span></summary>
				<div class="stack customer-profile">
					<div class="cols customer-details">
						<div><span class="muted small">Mobile</span><p>{customer.phone || 'Not provided'}</p></div>
						<div><span class="muted small">Email</span><p>{customer.email || 'Not provided'}</p></div>
						<div><span class="muted small">HERCO Points</span><p>{pointBalance(customer.id).toLocaleString('en-PH')}</p></div>
					</div>
					<h3>Booking history ({bookings.length})</h3>
					{#each bookings as b (b.id)}
						<div class="ledger"><div><span class="badge" data-status={b.status === 'confirmed' ? 'booked' : b.status}>{bookingStatusLabels[b.status]}</span> <b>{b.selection ? serviceLabel(b.selection) : serviceOf(b.serviceId).name}</b><p class="muted small">{b.bike} · {b.id}</p></div><span class="small">{fmtDate(b.date, { month: 'short', day: 'numeric' })} · {fmtSlot(b.slot)}</span></div>
					{:else}<p class="muted">No linked bookings yet.</p>{/each}
				</div>
			</details>
		{:else}<p class="muted">No matching customers.</p>{/each}
		{#if customers.length}
			<div class="row between">
				<span class="small muted" aria-live="polite">Showing {customerOffset + 1}–{Math.min(customerOffset + pageSize, customers.length)} of {customers.length} accounts</span>
				<Pager page={currentCustomerPage} pages={customerPages} label="Customers" onchange={(next) => customerPage = next} />
			</div>
		{/if}
	{:else if tab === 'HERCO Points'}
		<nav class="row" aria-label="HERCO Points sections">
			<a class="btn sm" class:ghost={showRedemptions} href={resolve(adminPath('HERCO Points'))} aria-current={!showRedemptions ? 'page' : undefined}><ActionIcon name="ranking" />Ranking &amp; rewards</a>
			<a class="btn sm" class:ghost={!showRedemptions} href={resolve(adminPath('HERCO Points', 'Redemptions'))} aria-current={showRedemptions ? 'page' : undefined}
				aria-label={'Redemptions, ' + redemptionCounts.pending + ' pending approval'}><ActionIcon name="gift" />
				Redemptions <span class="tab-count" aria-hidden="true">{redemptionCounts.pending}</span>
			</a>
		</nav>
		{#if !showRedemptions}
		<div class="admin-points-layout">
		<section class="stack">
		<div class="row between"><h3>HERCO Points ranking</h3>{#if canPerform('managePoints')}<button class="btn sm" disabled={!ranking.length} onclick={openPoints}><ActionIcon name="adjust" />Manage HERCO Points</button>{/if}</div>
		<p class="muted small">Search fan accounts and view their ranking. Sample accounts are fictional.</p>
		<div class="cols">
			<label>Find a fan<input type="search" bind:value={search} oninput={() => leaderboardPage = 1} placeholder="Name, email, phone or account ID" /></label>
			<label>Sort leaderboard<select bind:value={leaderboardSort} onchange={() => leaderboardPage = 1}>
				<option value="highest">Highest points first</option>
				<option value="lowest">Lowest points first</option>
				<option value="name">Fan name (A–Z)</option>
			</select></label>
		</div>
		<div class="card leaderboard">
			{#each sortedFans.slice((currentLeaderboardPage - 1) * pageSize, currentLeaderboardPage * pageSize) as { fan, rank } (fan.id)}
					<div class="rank-row">
						<b class="rank-number" class:podium={rank <= 3}>#{rank}</b>
						<div class="rank-fan"><b>{fan.name}</b><span class="muted small">{fan.email || (fan.demoFan ? 'Sample fan account' : 'No email on file')}</span>{#if fan.phone}<span class="muted small">{fan.phone}</span>{/if}</div>
						<strong class="rank-points">{pointBalance(fan.id)} <span class="small muted">points</span></strong>
					</div>
			{:else}<p class="muted">No fans found.</p>{/each}
		</div>
		<Pager page={currentLeaderboardPage} pages={leaderboardPages} label="Leaderboard" onchange={(next) => leaderboardPage = next} />
		</section>
		<aside class="card stack">
			<div class="rewards-heading"><h3>HERCO Rewards Program</h3>{#if canPerform('manageRewards')}<button class="btn sm" disabled={!rewardProgram.length} onclick={openReward}><ActionIcon name="edit" />Edit reward</button>{/if}</div>
			{#each rewardProgram as reward, index (index)}
				<div class="ledger reward-line">
					<div><b>{reward.name}</b>{#if reward.scope}<p class="small muted">{reward.scope}</p>{/if}</div>
					<strong class="reward-points">{reward.points.toLocaleString('en-PH')} <span class="small">points</span></strong>
				</div>
			{/each}
		</aside>
		</div>
		{#if canPerform('managePoints')}
		<dialog bind:this={pointsDialog} aria-labelledby="points-dialog-title">
			<div class="stack">
				<div class="dialog-heading row"><h3 id="points-dialog-title">Manage HERCO Points</h3><button class="close-dialog" aria-label="Close points popup" onclick={() => pointsDialog?.close()}><ActionIcon name="close" /></button></div>
				<label>Find a fan<input type="search" bind:value={pointsSearch} placeholder="Name, email, phone or account ID" oninput={() => {
					memberId = '';
					error = '';
					points = 1;
					correctionReason = '';
				}} /></label>
				{#if !selected && pointsQuery}
					<ul class="fan-results">
						{#each pointsMatches as fan (fan.id)}
							<li><button type="button" class="opt" onclick={() => { memberId = fan.id; pointsSearch = fan.name; }}>
								<b><ActionIcon name="user" /> {fan.name}</b>
								<span class="small muted">{fan.email || fan.id}{fan.phone ? ' · ' + fan.phone : ''}</span>
							</button></li>
						{:else}<li class="muted">No fans found.</li>{/each}
					</ul>
				{/if}
				{#if selected}
				<h3>{selected.name} · {pointBalance(selected.id)} points</h3>
				{#if error}<p class="error" role="alert">{error}</p>{/if}
				<form class="stack" onsubmit={(e) => {
					e.preventDefault();
					perform(() => {
						if (correctingPoints) correctPoints(selected.id, points, correctionReason);
						else grantPoints(selected.id, points);
						pointsDialog?.close();
					}, correctingPoints ? 'HERCO Points correction recorded.' : 'HERCO Points added.');
				}}>
					<label>Action<select bind:value={correctingPoints} onchange={() => { error = ''; points = 1; }}>
						<option value={false}>Add points</option><option value={true}>Correct points</option>
					</select></label>
					<label>{correctingPoints ? 'Adjustment (use a negative number to subtract)' : 'Points to add'}<input type="number" min={correctingPoints ? -pointBalance(selected.id) : 1} step="1" required bind:value={points} /></label>
					{#if correctingPoints}<label>Reason<input bind:value={correctionReason} required /></label>{/if}
					<div class="row"><button class="btn sm"><ActionIcon name={correctingPoints ? "save" : "add"} />{correctingPoints ? 'Save correction' : 'Add HERCO Points'}</button><button type="button" class="btn sm ghost" onclick={() => pointsDialog?.close()}><ActionIcon name="close" />Cancel</button></div>
				</form>
				<h3>Points history</h3>
				{#each ops.data.points.filter((entry) => entry.memberId === selected.id).toReversed() as entry (entry.id)}
					<div class="ledger"><div>{entry.reason}<p class="muted small">{new Date(entry.at).toLocaleString('en-PH', { timeZone: 'Asia/Manila', hour12: true })}</p></div><b>{entry.amount > 0 ? '+' : ''}{entry.amount}</b></div>
				{:else}<p class="muted">No points activity.</p>{/each}
				{/if}
			</div>
		</dialog>
		{/if}
		{#if canPerform('manageRewards')}
		<dialog bind:this={rewardDialog} aria-labelledby="reward-dialog-title">
			<form class="stack" onsubmit={(e) => { e.preventDefault(); perform(() => { editRewardTier(rewardIndex, { name: rewardTitle, scope: rewardScope, points: rewardCost }); rewardDialog?.close(); }, 'Reward updated.'); }}>
				<div class="dialog-heading row"><h3 id="reward-dialog-title">Edit reward</h3><button type="button" class="close-dialog" aria-label="Close reward popup" onclick={() => rewardDialog?.close()}><ActionIcon name="close" /></button></div>
				{#if error}<p class="error" role="alert">{error}</p>{/if}
				<label>Reward<select bind:value={rewardIndex} onchange={(e) => selectReward(Number(e.currentTarget.value))}>
					{#each rewardProgram as reward, index (index)}<option value={index}>{reward.name}{reward.scope ? ' · ' + reward.scope : ''}</option>{/each}
				</select></label>
				<label>Reward name<input required bind:value={rewardTitle} /></label>
				<label>Scope (optional)<input bind:value={rewardScope} placeholder="e.g. Small parts" /></label>
				<label>Points required<input type="number" min="1" step="1" required bind:value={rewardCost} /></label>
				<div class="row"><button class="btn sm"><ActionIcon name="save" />Save reward</button><button type="button" class="btn sm ghost" onclick={() => rewardDialog?.close()}><ActionIcon name="close" />Cancel</button></div>
			</form>
		</dialog>
		{/if}
		{:else}
		<div class="card stack">
			<h3>Redemptions</h3>
			<dl class="inventory-metrics redemption-metrics">
				{#each redemptionStatuses as status (status.value)}
					<div data-redemption-status={status.value}><dt><span class="badge" data-status={status.tone}>{status.label}</span></dt><dd>{redemptionCounts[status.value]}</dd></div>
				{/each}
			</dl>
			<div class="cols">
				<label>Search redemptions<input type="search" bind:value={redemptionSearch} oninput={() => redemptionPage = 1} placeholder="Customer name, email, phone or AR reference" /></label>
				<label>Status<select bind:value={redemptionFilter} onchange={() => redemptionPage = 1}>
					<option value="all">All statuses</option>
					{#each redemptionStatuses as status (status.value)}<option value={status.value}>{status.label}</option>{/each}
				</select></label>
				<label>Sort redemptions<select bind:value={redemptionSort} onchange={() => redemptionPage = 1}>
					<option value="oldest">Oldest first</option>
					<option value="newest">Newest first</option>
				</select></label>
			</div>
			<p class="small muted" aria-live="polite">{visibleRedemptions.length} {visibleRedemptions.length === 1 ? 'redemption' : 'redemptions'}</p>
			{#each visibleRedemptions.slice((currentRedemptionPage - 1) * pageSize, currentRedemptionPage * pageSize) as { receipt, status } (receipt.id)}
				<details class="redemption-row">
					<summary>
						<span class="redemption-summary">
							<span><b>{receipt.memberName}</b><span class="small muted redemption-meta">{receipt.reward} · {receipt.cost.toLocaleString('en-PH')} points</span></span>
							<span class="small muted">{redemptionDate.format(new Date(receipt.at))} PH</span>
							<span class="badge" data-status={redemptionStatuses.find(option => option.value === status)?.tone}>{rewardStatus(receipt)}</span>
						</span>
					</summary>
					<div class="stack">
						<RewardReceipt {receipt} />
						{#if receipt.status === 'pending' && canPerform('approveRewards')}
							<div><button class="btn sm" onclick={() => perform(() => approveRewardReceipt(receipt.id), 'Reward redemption approved.')}><ActionIcon name="check" />Approve redemption</button></div>
						{:else if receipt.status !== 'pending' && receipt.status !== 'claimed' && canPerform('claimRewards')}
							<div><button class="btn sm complete-action" onclick={() => perform(() => claimRewardReceipt(receipt.id), 'Reward AR marked as claimed.')}><ActionIcon name="check" />Mark as claimed</button></div>
						{/if}
					</div>
				</details>
			{:else}<p class="muted">No matching reward redemptions.</p>{/each}
			<Pager page={currentRedemptionPage} pages={redemptionPages} label="Redemptions" onchange={(next) => redemptionPage = next} />
		</div>
		{/if}
	{:else if tab === 'Inventory'}
		<div class="row inventory-heading">
		{#if canManageInventory}
		<div class="row inventory-actions">
			<button type="button" class="btn sm" onclick={() => {
				error = '';
				if (!units.includes(unit)) unit = units[0] ?? '';
				newItemDialog?.showModal();
			}}><ActionIcon name="add" />Create new inventory item</button>
			<button type="button" class="btn sm ghost" onclick={() => openStock()}><ActionIcon name="adjust" />Update existing stock</button>
			<button type="button" class="btn sm ghost" onclick={() => openInventoryOptions('unit')}><ActionIcon name="box" />Manage units and categories</button>
		</div>
		{/if}
		</div>
		<section class="card stack" aria-labelledby="inventory-overview-title">
			<h3 id="inventory-overview-title">Inventory overview</h3>
			<dl class="inventory-metrics stock-metrics">
				<div><dt>All items</dt><dd>{ops.data.stock.length}</dd></div>
				<div><dt><span class="badge" data-status="done">In stock</span></dt><dd>{inStock}</dd></div>
				<div><dt><span class="badge" data-status="pending">Low stock</span></dt><dd>{lowStock}</dd></div>
				<div><dt><span class="badge" data-status="cancelled">Out of stock</span></dt><dd>{outOfStock}</dd></div>
			</dl>
		</section>
		{#if canManageInventory}
		<dialog bind:this={optionDialog} aria-labelledby="stock-option-title">
			<form class="stack" onsubmit={(e) => {
				e.preventDefault();
				perform(() => {
					if (renamingOption) {
						renameStockOption(optionKind, previousOption, optionName);
						const name = optionName.trim();
						if (optionKind === 'unit' && unit === previousOption) unit = name;
						if (optionKind === 'category') {
							if (newItemCategory === previousOption) newItemCategory = name;
							if (categoryFilter === 'category:' + previousOption) categoryFilter = 'category:' + name;
						}
					} else {
						addStockOption(optionKind, optionName);
						if (addingOptionToNewItem) {
							if (optionKind === 'unit') unit = optionName.trim();
							else newItemCategory = optionName.trim();
						}
					}
					optionDialog?.close();
				}, renamingOption ? 'Inventory option renamed.' : optionKind === 'unit' ? 'Unit added.' : 'Category added.');
			}}>
				<h3 id="stock-option-title">{addingOptionToNewItem ? 'New ' + optionKind : 'Manage units and categories'}</h3>
				{#if error}<p class="error" role="alert">{error}</p>{/if}
				{#if !addingOptionToNewItem}
				<div class="cols">
					<label>Type
						<select bind:value={optionKind} onchange={() => { renamingOption = false; resetStockOption(); }}>
							<option value="unit">Unit</option>
							<option value="category">Category</option>
						</select>
					</label>
					<label>Action
						<select bind:value={renamingOption} onchange={resetStockOption}>
							<option value={false}>Add new</option>
							<option value={true} disabled={!existingOptions.length}>Rename existing</option>
						</select>
					</label>
				</div>
				{/if}
				{#if renamingOption}
					<label>Existing {optionKind}
						<select bind:value={previousOption} onchange={(e) => optionName = e.currentTarget.value} required>
							<option value="">Select {optionKind}</option>
							{#each existingOptions as option (option)}<option value={option}>{option}</option>{/each}
						</select>
					</label>
					<p class="small muted">Renaming updates every item using this {optionKind}.</p>
				{/if}
				<label>{renamingOption ? 'New name' : 'Name'}<input bind:value={optionName} required /></label>
				<div class="row"><button class="btn sm"><ActionIcon name="save" />Save</button><button type="button" class="btn sm ghost" onclick={() => optionDialog?.close()}><ActionIcon name="close" />Cancel</button></div>
			</form>
		</dialog>
		<dialog class="inventory-form" bind:this={newItemDialog} aria-labelledby="new-item-dialog-title">
			<form class="stack" onsubmit={(e) => {
				e.preventDefault();
				perform(() => {
					addStock(stockName, unit, quantity, minimum, newItemCategory, $state.snapshot(newStockDetails));
					newStockDetails = {};
					newItemCategory = '';
					stockName = '';
					unit = 'bottle';
					quantity = 0;
					minimum = 0;
					newItemDialog?.close();
				}, 'Stock item added.');
			}}>
				<div class="dialog-heading row"><h3 id="new-item-dialog-title">Create new inventory item</h3><button type="button" class="close-dialog" aria-label="Close new inventory item popup" onclick={() => newItemDialog?.close()}><ActionIcon name="close" /></button></div>
				{#if error}<p class="error" role="alert">{error}</p>{/if}
				<label>Item name<input bind:value={stockName} placeholder="e.g. Ceramic coating" required /></label>
				<div class="cols">
					<div>
						<div class="row inventory-heading"><label for="new-stock-category">Category (optional)</label><button type="button" class="inventory-option-link" onclick={() => openInventoryOptions('category', true)}><ActionIcon name="add" />New category</button></div>
						<select id="new-stock-category" bind:value={newItemCategory}><option value="">Uncategorized</option>{#each categories as category (category)}<option value={category}>{category}</option>{/each}</select>
					</div>
					<div>
						<div class="row inventory-heading"><label for="new-stock-unit">Unit of measure</label><button type="button" class="inventory-option-link" onclick={() => openInventoryOptions('unit', true)}><ActionIcon name="add" />New unit</button></div>
						<select id="new-stock-unit" bind:value={unit} required>{#each units as unitOption (unitOption)}<option value={unitOption}>{unitOption}</option>{/each}</select>
					</div>
				</div>
				<fieldset class="inventory-fields"><legend>Stock levels</legend>
					<div class="cols stock-level-fields">
						<label>Opening stock<input type="number" min="0" step="0.001" bind:value={quantity} required /></label>
						<label>Reorder threshold<input type="number" min="0" step="0.001" bind:value={minimum} required /></label>
						<label>Storage capacity (optional)<input type="number" min="0" step="0.001" bind:value={newStockDetails.capacity} /></label>
					</div>
				</fieldset>
				{@render stockDetailsFields(newStockDetails)}
				<div class="row inventory-form-footer"><button type="button" class="btn sm ghost" onclick={() => newItemDialog?.close()}><ActionIcon name="close" />Cancel</button><button class="btn sm"><ActionIcon name="add" />Create inventory item</button></div>
			</form>
		</dialog>
		{/if}
		<section class="card stack stock-panel" aria-labelledby="stock-on-hand-title">
			<div class="row inventory-heading"><h3 id="stock-on-hand-title">Stock on hand</h3><span class="small muted">{visibleStock.length} of {ops.data.stock.length} items shown</span></div>
			<div class="cols">
				<label>Search supplies<input type="search" bind:value={stockSearch} oninput={() => stockPage = 1} placeholder="e.g. Ceramic coating" /></label>
				<label>Category
					<select bind:value={categoryFilter} onchange={() => stockPage = 1}>
						<option value="">All categories</option>
						<option value="uncategorized">Uncategorized</option>
						{#each categories as category (category)}<option value={'category:' + category}>{category}</option>{/each}
					</select>
				</label>
				<label>Stock status
					<select bind:value={stockFilter} onchange={() => stockPage = 1}>
						<option value="all">All items</option>
						<option value="healthy">In stock</option>
						<option value="low">Low stock</option>
						<option value="out">Out of stock</option>
					</select>
				</label>
			</div>
			{#if visibleStock.length}
			<!-- svelte-ignore a11y_no_noninteractive_tabindex (Keyboard users need to scroll the ledger horizontally.) -->
			<div class="stock-table" role="region" aria-labelledby="stock-on-hand-title" tabindex="0">
			<table>
				<thead><tr><th scope="col">Item</th><th scope="col">Category</th><th scope="col">Stock status</th><th scope="col">Reorder threshold</th>{#if canManageInventory}<th scope="col">Inventory actions</th>{/if}</tr></thead>
				<tbody>
			{#each visibleStock.slice((currentStockPage - 1) * pageSize, currentStockPage * pageSize) as item (item.id)}
				{@const health = stockHealth(item.quantity, item.minimum)}
				<tr class:low-stock={health === 'low'}>
					<th scope="row"><b>{item.name}</b><p class="small muted">{item.quantity} {item.unit} on hand{item.details?.location ? ' · ' + item.details.location : ''}</p></th>
					<td>{item.category || 'Uncategorized'}</td>
					<td><span class="badge" data-status={health === 'out' ? 'cancelled' : health === 'low' ? 'pending' : 'done'}>{health === 'out' ? 'Out of stock' : health === 'low' ? 'Low stock' : 'In stock'}</span></td>
					<td class="stock-gauge">
						<progress aria-label={'Stock compared with reorder threshold for ' + item.name} max={Math.max(item.minimum * 2, item.quantity, 1)} value={item.quantity} data-health={health}></progress>
						<span class="small muted">{item.quantity} on hand · Reorder at {item.minimum}</span>
					</td>
					{#if canManageInventory}<td><div class="row stock-row-actions">
						<button class="btn sm ghost stock-in" aria-label={'Stock in for ' + item.name} onclick={() => openStock(item.id)}><ActionIcon name="in" />Stock in</button>
						<button class="btn sm ghost stock-out" aria-label={'Stock out for ' + item.name} disabled={!item.quantity} onclick={() => openStock(item.id, 'use')}><ActionIcon name="out" />Stock out</button>
						<button type="button" class="btn sm ghost" aria-label={'Edit item ' + item.name} onclick={() => {
							error = '';
							itemDraft = { id: item.id, name: item.name, unit: item.unit, minimum: item.minimum, category: item.category ?? '' };
							editStockDetails = { ...item.details };
							editItemDialog?.showModal();
						}}><ActionIcon name="edit" />Edit</button>
					</div></td>{/if}
				</tr>
			{/each}
				</tbody>
			</table>
			</div>
			<Pager page={currentStockPage} pages={stockPages} label="Stock on hand" onchange={(next) => stockPage = next} />
			{:else}<p class="muted">No supplies match this view.</p>{/if}
		</section>
		{#if canManageInventory}
		<dialog class="inventory-form" bind:this={editItemDialog} aria-labelledby="edit-item-dialog-title">
			<form class="stack" onsubmit={(e) => {
				e.preventDefault();
				perform(() => {
					editStockItem(itemDraft.id, itemDraft.name, itemDraft.unit, itemDraft.minimum, itemDraft.category, $state.snapshot(editStockDetails));
					if (categoryFilter.startsWith('category:') && !categories.includes(categoryFilter.slice('category:'.length))) categoryFilter = '';
					editItemDialog?.close();
				}, 'Inventory item updated.');
			}}>
				<h3 id="edit-item-dialog-title">Edit inventory item</h3>
				{#if error}<p class="error" role="alert">{error}</p>{/if}
				<label>Item name<input bind:value={itemDraft.name} required /></label>
				<label>Category (optional)<select bind:value={itemDraft.category}><option value="">Uncategorized</option>{#each categories as category (category)}<option value={category}>{category}</option>{/each}</select></label>
				<div class="cols">
					<label>Unit<select bind:value={itemDraft.unit} required>{#each units as unitOption (unitOption)}<option value={unitOption}>{unitOption}</option>{/each}</select></label>
					<label>Low stock threshold<input type="number" min="0" step="0.001" bind:value={itemDraft.minimum} required /></label>
					<label>Storage capacity (optional)<input type="number" min="0" step="0.001" bind:value={editStockDetails.capacity} /></label>
				</div>
				{@render stockDetailsFields(editStockDetails)}
				<div class="row"><button class="btn sm"><ActionIcon name="save" />Save changes</button><button type="button" class="btn sm ghost" onclick={() => editItemDialog?.close()}><ActionIcon name="close" />Cancel</button></div>
			</form>
		</dialog>
		<dialog bind:this={stockDialog} aria-labelledby="stock-dialog-title">
			<form class="stack" onsubmit={(e) => {
				e.preventDefault();
				perform(() => {
					if (!Number.isFinite(adjustment) || adjustment <= 0) throw new Error('Enter a positive quantity.');
					adjustStock(stockId, stockMode === 'add' ? adjustment : -adjustment, stockReason.trim() || (stockMode === 'add' ? 'Stock received' : 'Used for service'));
					stockDialog?.close();
				}, stockMode === 'add' ? 'Stock added to the existing item.' : 'Usage recorded.');
			}}>
				<div class="dialog-heading row"><h3 id="stock-dialog-title">{stockMode === 'add' ? 'Add stock' : 'Record usage'}</h3><button type="button" class="close-dialog" aria-label="Close stock popup" onclick={() => stockDialog?.close()}><ActionIcon name="close" /></button></div>
				{#if error}<p class="error" role="alert">{error}</p>{/if}
				<label>Item<select bind:value={stockId} required><option value="">Select item</option>{#each ops.data.stock as item (item.id)}<option value={item.id}>{item.name}</option>{/each}</select></label>
				<label>Update type<select bind:value={stockMode}><option value="add">Add stock</option><option value="use">Record usage</option></select></label>
				{#if selectedStock}<p>Current stock <b>{selectedStock.quantity} {selectedStock.unit}</b></p>{/if}
				<label>Quantity {selectedStock ? '(' + selectedStock.unit + ')' : ''}<input type="number" min="0.001" step="0.001" bind:value={adjustment} required /></label>
				{#if selectedStock && Number.isFinite(adjustment)}
					<p>Stock after update <b>{Math.round((selectedStock.quantity + (stockMode === 'add' ? adjustment : -adjustment)) * 1000) / 1000} {selectedStock.unit}</b></p>
				{/if}
				<label>Note (optional)<input bind:value={stockReason} placeholder={stockMode === 'add' ? 'e.g. Supplier delivery' : 'e.g. Ceramic coating service'} /></label>
				<div class="row"><button class="btn sm"><ActionIcon name={stockMode === "add" ? "in" : "save"} />{stockMode === 'add' ? 'Add stock' : 'Save usage'}</button><button type="button" class="btn sm ghost" onclick={() => stockDialog?.close()}><ActionIcon name="close" />Cancel</button></div>
			</form>
		</dialog>
		{/if}
		<details class="card stock-history" open><summary>Stock history</summary>
			<label>Filter stock history<select bind:value={historyItem} onchange={() => historyPage = 1}><option value="">All items</option>{#each ops.data.stock as item (item.id)}<option value={item.id}>{item.name}</option>{/each}</select></label>
			{#each stockHistory.slice((currentHistoryPage - 1) * pageSize, currentHistoryPage * pageSize) as entry (entry.id)}<div class="ledger"><div><b>{ops.data.stock.find((item) => item.id === entry.itemId)?.name}</b><p class="small muted">{entry.reason} · {new Date(entry.at).toLocaleString('en-PH', { timeZone: 'Asia/Manila', dateStyle: 'medium', timeStyle: 'short', hour12: true })}</p></div><b class="badge" data-status={entry.amount < 0 ? 'cancelled' : 'done'}>{entry.amount > 0 ? '+' : ''}{entry.amount}</b></div>{:else}<p class="muted">No stock movements for this view.</p>{/each}
			<Pager page={currentHistoryPage} pages={historyPages} label="Stock history" onchange={(next) => historyPage = next} />
		</details>
	{:else if tab === 'Reports'}
			{#await import('./AdminReports.svelte')}
					<p role="status">Loading reports…</p>
				{:then reports}
					<reports.default showIncome={canPerform('viewIncome')} />
				{:catch}
					<p class="error" role="alert">Reports could not be loaded. Reload the page and try again.</p>
				{/await}
	{/if}
	<DemoBookingSheet bind:booking={detail} />
</div>



{#snippet stockDetailsFields(details: StockDetails)}
	<fieldset class="inventory-fields"><legend>Supplier &amp; costs <span class="small muted">(optional)</span></legend>
		<div class="cols">
			<label>Unit cost (₱)<input type="number" min="0" step="0.01" bind:value={details.unitCost} /></label>
			<label>Supplier<input bind:value={details.supplier} /></label>
		</div>
	</fieldset>
{/snippet}

<style>
	.customer-total { display: grid; gap: .25rem; }
	.customer-total b { font-size: 1.6rem; }
	.customer-record { padding: 0; overflow-wrap: anywhere; }
	.customer-record > summary { padding: .65rem .9rem; cursor: pointer; }
	.customer-record[open] > summary { background: var(--panel-2); border-radius: 6px 6px 0 0; }
	.customer-record-meta { display: inline-flex; flex-wrap: wrap; align-items: center; gap: .4rem; margin-inline-start: .55rem; color: var(--muted); font-size: .85rem; }
	.customer-record .customer-profile { padding: .9rem; }
	.customer-details { background: var(--bg); border: 1px solid var(--line); padding: .7rem; border-radius: 4px; }
	.inventory-metrics.redemption-metrics > div {
		background: var(--panel);
		border: 1px solid var(--status-border);
	}
	.redemption-metrics [data-redemption-status="pending"] {
		--status-border: var(--warn-line);
	}
	.redemption-metrics [data-redemption-status="approved"] {
		--status-border: var(--info-line);
	}
	.redemption-metrics [data-redemption-status="claimed"] {
		--status-border: var(--ok-line);
	}
	.inventory-heading { justify-content: space-between; }
	.inventory-option-link { border: 0; background: transparent; color: var(--accent); font: inherit; font-size: .85rem; font-weight: 700; cursor: pointer; padding: .25rem; }
	.inventory-option-link:hover { text-decoration: underline; }
	.inventory-actions, .stock-row-actions { gap: .35rem; }
	.inventory-actions .btn, .stock-row-actions .btn, .inventory-form .btn {
		clip-path: none; border-radius: .25rem; font-style: normal;
	}
	.stock-panel { min-width: 0; }
	.inventory-metrics.stock-metrics > div { align-content: start; background: var(--panel); border: 1px solid var(--line); }
	.stock-metrics > div:nth-child(2) { border-color: var(--ok-line); }
	.stock-metrics > div:nth-child(3) { border-color: var(--warn-line); }
	.stock-metrics dd { font-variant-numeric: tabular-nums; }
	.stock-table { overflow-x: auto; border: 1px solid var(--line); border-radius: .35rem; }
	.stock-table table { width: 100%; min-width: 850px; border-collapse: collapse; font-size: .9rem; }
	.stock-table th, .stock-table td { padding: .55rem .65rem; text-align: left; border-bottom: 1px solid var(--line); }
	.stock-table thead th { background: var(--panel-2); text-transform: uppercase; font-size: .75rem; letter-spacing: .03em; }
	.stock-table tbody th { font-weight: 400; }
	.stock-table tr:last-child td, .stock-table tbody tr:last-child th { border-bottom: 0; }
	.stock-row-actions { justify-content: flex-end; flex-wrap: nowrap; }
	.stock-table th:last-child { text-align: right; }
	.stock-gauge progress { display: block; width: 100%; height: .5rem; }
	.stock-gauge span { white-space: nowrap; }
	.stock-panel, .stock-table {
		--stock-border: light-dark(#eddcd7, #465467);
		--stock-blue: light-dark(#edf3ff, #242d3a);
		--stock-muted: light-dark(#765851, #b9c4d4);
		border-color: var(--stock-border);
	}
	.stock-panel input, .stock-panel select { background: var(--panel); border-color: var(--stock-border); color: var(--text); }
	.stock-table { background: var(--panel); color: var(--text); }
	.stock-table th, .stock-table td { border-color: light-dark(#f0e7e4, #343e4c); }
	.stock-table thead th { background: var(--panel); color: var(--stock-muted); }
	.stock-table .muted, .stock-table td:nth-child(2) { color: var(--stock-muted); }
	.stock-table .low-stock { background: color-mix(in srgb, var(--warn-bg) 38%, var(--panel)); }
	.stock-table .low-stock .muted { color: var(--warn); }
	.stock-table .badge { display: inline-block; white-space: nowrap; border: 1px solid; border-radius: .18rem; padding: .2rem .4rem; font-family: inherit; font-size: .72rem; font-weight: 700; line-height: 1.2; letter-spacing: .025em; }
	.stock-table .badge[data-status="done"] { border-color: var(--ok-line); }
	.stock-table .badge[data-status="pending"] { border-color: var(--warn-line); }
	.stock-table .badge[data-status="cancelled"] { border-color: var(--bad-line); }
	.stock-row-actions .btn { background: var(--stock-blue); color: var(--text); border: 1px solid var(--stock-border); white-space: nowrap; padding: .35rem .55rem; font-family: inherit; font-size: .75rem; font-weight: 700; line-height: 1.2; }
	.stock-row-actions .btn:last-child { background: var(--panel); color: var(--stock-muted); }
	.stock-row-actions .btn:last-child:hover { background: var(--stock-blue); }
	.stock-row-actions .stock-in { background: var(--ok-bg); color: var(--ok); border-color: var(--ok-line); }
	.stock-row-actions .stock-out { background: var(--bad-bg); color: var(--bad); border-color: var(--bad-line); }
	.stock-row-actions .stock-in:hover:not(:disabled) { background: color-mix(in srgb, var(--ok-bg) 85%, var(--ok)); }
	.stock-row-actions .stock-out:hover:not(:disabled) { background: color-mix(in srgb, var(--bad-bg) 85%, var(--bad)); }
	.stock-gauge progress {
		--gauge-track: var(--info-bg);
		--gauge-fill: light-dark(#00936b, #61c99d);
		appearance: none; border: 0; border-radius: 1rem; background: var(--gauge-track); overflow: hidden;
	}
	.stock-gauge progress[data-health="low"] { --gauge-track: var(--warn-bg); --gauge-fill: light-dark(#d78300, #f0b85f); }
	.stock-gauge progress::-webkit-progress-bar { background: var(--gauge-track); border-radius: 1rem; }
	.stock-gauge progress::-webkit-progress-value { background: var(--gauge-fill); border-radius: 1rem; }
	.stock-gauge progress::-moz-progress-bar { background: var(--gauge-fill); border-radius: 1rem; }
	.stock-history label { max-width: 20rem; margin-block: .65rem; }
	dialog.inventory-form { width: min(860px, calc(100vw - 32px)); }
	.inventory-fields { min-inline-size: 0; margin: 0; padding: .8rem; border: 1px solid var(--line); border-radius: .4rem; }
	.inventory-fields legend { padding-inline: .35rem; font-weight: 700; }
	.stock-level-fields label { background: var(--panel-2); padding: .6rem; border-radius: .3rem; }
	.stock-level-fields label:nth-child(2) { border-inline-start: 3px solid var(--accent); }
	.inventory-form-footer { justify-content: space-between; border-top: 1px solid var(--line); padding-top: .75rem; }
	.redemption-row { border-top: 1px solid var(--line); padding-block: .75rem; }
	.redemption-row[open] summary { margin-bottom: .75rem; }
	.redemption-summary { display: inline-flex; flex-wrap: wrap; align-items: center; gap: .35rem .9rem; vertical-align: middle; }
	.redemption-meta { display: block; }
	.fan-results { display: grid; gap: .4rem; list-style: none; padding: 0; margin: 0; max-height: 16rem; overflow: auto; }
	.fan-results button { display: grid; width: 100%; overflow-wrap: anywhere; }
	.rewards-heading, .reward-line { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: .6rem; align-items: baseline; }
	.rewards-heading { align-items: center; }
	.rewards-heading .btn, .reward-points { white-space: nowrap; }
	.reward-points { font-size: 1.2rem; text-align: right; }
	.admin-points-layout { display: grid; grid-template-columns: minmax(0, 2fr) minmax(0, 1fr); gap: 1rem; align-items: start; }
	.rank-fan { overflow-wrap: anywhere; }
	@media (max-width: 900px) { .admin-points-layout { grid-template-columns: minmax(0, 1fr); } }
	.inventory-metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: .75rem; margin: 0; }
	.inventory-metrics > div { display: grid; gap: .35rem; padding: .75rem; border-radius: .35rem; background: var(--panel-2); }
	.inventory-metrics dd { margin: 0; font-size: 1.5rem; font-weight: 700; }
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
	.close-dialog { display: grid; place-items: center; width: 40px; height: 40px; border: 1px solid var(--line); border-radius: 50%; background: var(--panel-2); color: var(--text); font-size: 1.25rem; cursor: pointer; }
	.customer-profile { padding-top: 18px; }
	.rank-row { display: flex; flex-wrap: wrap; align-items: center; gap: 16px; padding-block: 18px; border-bottom: 1px solid var(--line); }
	.rank-number { font: italic 800 1.8rem var(--display); color: var(--muted); min-width: 40px; }
	.podium { color: var(--accent); }
	.rank-fan { display: grid; flex: 1 1 160px; gap: 4px; }
	.rank-points { font-size: 1.3rem; min-width: 95px; }
	.rank-points span { display: block; }
	.list-head { justify-content: space-between; }
	.list-head h2 { font-size: 1.35rem; }

	.ledger { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; padding-block: 12px; border-bottom: 1px solid var(--line); }
	.success { color: var(--ok); }
	summary { cursor: pointer; }
	.cols { grid-template-columns: repeat(auto-fit, minmax(min(100%, 230px), 1fr)); }
</style>