<script lang="ts">
	import { addDays, fmtDate, isOpenDay, today } from './dates';
	import { bookingsOn, dayStatus } from './store.svelte';

	let { value, onpick }: { value: string; onpick: (date: string) => void } = $props();
	let month = $state('');
	const displayedMonth = $derived(month || value.slice(0, 7));
	const firstDay = $derived(displayedMonth + '-01');
	const leading = $derived((new Date(firstDay + 'T00:00:00Z').getUTCDay() + 6) % 7);
	const days = $derived(new Date(Number(displayedMonth.slice(0, 4)), Number(displayedMonth.slice(5, 7)), 0).getDate());
	const visibleDates = $derived(Array.from({ length: Math.ceil((leading + days) / 7) * 7 }, (_, i) => addDays(firstDay, i - leading)));

	function shiftMonth(amount: number) {
		const date = new Date(firstDay + 'T00:00:00Z');
		date.setUTCMonth(date.getUTCMonth() + amount);
		if (date.getUTCFullYear() < 1 || date.getUTCFullYear() > 9999) return;
		month = date.toISOString().slice(0, 7);
	}
	function goToday() {
		month = today().slice(0, 7);
		onpick(today());
	}
</script>

<div class="calendar stack">
	<div class="row calendar-toolbar">
		<div>
			<p class="eyebrow">Booking calendar</p>
			<h3>{fmtDate(firstDay, { month: 'long' })} <span>{fmtDate(firstDay, { year: 'numeric' })}</span></h3>
		</div>
		<div class="row calendar-controls">
			<label class="month-picker"><span class="sr-only">Jump to month</span><input aria-label="Jump to month" type="month" value={displayedMonth} onchange={(e) => { if (/^\d{4}-\d{2}$/.test(e.currentTarget.value)) month = e.currentTarget.value; }} /></label>
			<button type="button" class="today-button" onclick={goToday}>Today</button>
			<div class="row month-arrows">
			<button type="button" class="month-arrow" aria-label="Previous month" onclick={() => shiftMonth(-1)}>‹</button>
			<button type="button" class="month-arrow" aria-label="Next month" onclick={() => shiftMonth(1)}>›</button>
			</div>
		</div>
	</div>
	<div class="month-grid" aria-label="Booking calendar">
		{#each ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as weekday}<span class="weekday small muted">{weekday}</span>{/each}
		{#each visibleDates as date (date)}
			{@const bookings = bookingsOn(date)}
			{@const count = bookings.length}
			{@const pending = bookings.filter((b) => b.status === 'pending').length}
			{@const outside = !date.startsWith(displayedMonth)}
			{@const blocked = dayStatus(date) === 'blocked'}
			<button
				type="button"
				class="day"
				class:selected={value === date}
				class:closed={!isOpenDay(date)}
				class:is-today={date === today()}
				class:outside
				aria-label={fmtDate(date) + ', ' + count + ' bookings' + (blocked ? ', blocked' : !isOpenDay(date) ? ', closed' : '')}
				aria-pressed={value === date}
				aria-current={date === today() ? 'date' : undefined}
				onclick={() => { if (outside) month = date.slice(0, 7); onpick(date); }}
			>
				<span class="date-line"><time datetime={date}>{fmtDate(date, { day: 'numeric' })}</time>{#if count}<span class="booking-count">{count}</span>{/if}</span>
				{#if !outside}
					<span class="day-caption">
						{#if blocked}Blocked
						{:else if !isOpenDay(date)}Closed
						{:else if pending}<span class="status-dot pending"></span><span>{pending} pending</span>
						{:else if count}<span class="status-dot confirmed"></span><span>{count} booked</span>
						{:else}<span class="empty-caption">No bookings</span>{/if}
					</span>
				{/if}
			</button>
		{/each}
	</div>
	<div class="calendar-footer row">
		<p class="small"><b>{fmtDate(value, { weekday: 'short', month: 'short', day: 'numeric' })}</b><span class="muted"> · {bookingsOn(value).length} bookings</span></p>
		<div class="row legend small muted"><span><i class="status-dot pending"></i> Pending</span><span><i class="status-dot confirmed"></i> Booked</span></div>
	</div>
</div>

<style>
	.calendar {
		gap: 0;
		overflow: hidden;
		background: var(--panel);
		border: 1px solid var(--line);
		border-radius: 12px;
	}
	.calendar-toolbar { justify-content: space-between; gap: 16px; padding: 20px 24px; }
	.calendar-toolbar .eyebrow { font-size: 0.75rem; margin-bottom: 8px; }
	.calendar-toolbar h3 { font-size: 2rem; }
	.calendar-toolbar h3 span { color: var(--muted); font-weight: 600; }
	.calendar-controls { gap: 12px; }
	.month-arrows { gap: 2px; }
	.month-arrow, .today-button { min-width: 40px; height: 40px; border: 1px solid var(--line); border-radius: 6px; background: var(--panel-2); color: var(--text); cursor: pointer; }
	.month-arrow { font-size: 1.5rem; }
	.today-button { padding-inline: 14px; font: 600 0.85rem var(--body); }
	.month-arrow:hover, .today-button:hover { border-color: var(--accent); }
	.month-picker input { min-height: 40px; margin: 0; padding: 6px 10px; font-size: 0.85rem; background: var(--bg); }
	.month-grid { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); padding: 0 16px; }
	.weekday { text-align: left; padding: 10px 12px; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.08em; border-bottom: 1px solid var(--line); }
	.day { min-height: 76px; display: flex; flex-direction: column; gap: 8px; padding: 10px 12px; color: var(--text); background: transparent; border: 0; border-bottom: 1px solid var(--line); border-radius: 0; cursor: pointer; text-align: left; }
	.day:hover { background: var(--panel-2); }
	.date-line { width: 100%; display: flex; align-items: center; justify-content: space-between; gap: 3px; }
	time { display: grid; place-items: center; width: 28px; height: 28px; border: 1px solid transparent; border-radius: 50%; font: 600 0.95rem var(--body); }
	.booking-count { min-width: 22px; padding: 1px 6px; border-radius: 5px; color: var(--text); background: var(--panel-2); font-size: 0.75rem; font-weight: 700; }
	.day-caption { display: flex; align-items: center; gap: 5px; color: var(--muted); font-size: 0.72rem; }
	.status-dot { display: inline-block; flex-shrink: 0; width: 6px; height: 6px; border-radius: 50%; }
	.pending { background: var(--warn); }
	.confirmed { background: var(--ok); }
	.closed { background: rgb(0 0 0 / 14%); }
	.closed time { color: var(--muted); }
	.outside time { color: var(--muted); opacity: 0.45; }
	.selected { background: color-mix(in srgb, var(--accent) 9%, var(--panel)); border-radius: 6px; box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent) 45%, transparent); }
	.selected time { color: var(--accent-ink); background: var(--accent); }
	.is-today:not(.selected) time { border-color: var(--accent); color: var(--accent); }
	.calendar-footer { justify-content: space-between; padding: 16px 24px; }
	.legend span { display: inline-flex; align-items: center; gap: 6px; }
	.sr-only { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
	@media (max-width: 600px) {
		.calendar-toolbar { padding: 16px; }
		.calendar-controls { width: 100%; justify-content: space-between; gap: 6px; }
		.month-picker { flex: 1; max-width: 180px; }
		.month-picker input { width: 100%; }
		.month-grid { padding-inline: 6px; }
		.weekday { padding: 8px 2px; text-align: center; font-size: 0.65rem; }
		.day { min-height: 66px; padding: 7px 3px; }
		.date-line { gap: 0; }
		time { width: 25px; height: 25px; font-size: 0.85rem; }
		.booking-count { min-width: 15px; padding: 0 3px; font-size: 0.65rem; }
		.day-caption { font-size: 0.58rem; gap: 3px; }
		.empty-caption { display: none; }
		.calendar-footer { padding: 12px; gap: 10px; }
	}
</style>
