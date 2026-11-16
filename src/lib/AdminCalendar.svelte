<script lang="ts">
	import ActionIcon from '#lib/ActionIcon.svelte';
	import { addDays, fmtDate, today } from './dates';
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
		<div class="row month-arrows">
			<button type="button" class="month-arrow" aria-label="Previous month" onclick={() => shiftMonth(-1)}><ActionIcon name="left" /></button>
			<button type="button" class="month-arrow" aria-label="Next month" onclick={() => shiftMonth(1)}><ActionIcon name="right" /></button>
		</div>
		<div class="row calendar-controls">
			<label class="month-picker"><span class="sr-only">Jump to month</span><input aria-label="Jump to month" type="month" value={displayedMonth} onchange={(e) => { if (/^\d{4}-\d{2}$/.test(e.currentTarget.value)) month = e.currentTarget.value; }} /></label>
			<button type="button" class="today-button" onclick={goToday}><ActionIcon name="calendar" />Today</button>
		</div>
	</div>
	<div class="month-grid" aria-label="Booking calendar">
		{#each ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as weekday}<span class="weekday small muted">{weekday}</span>{/each}
		{#each visibleDates as date (date)}
			{@const bookings = bookingsOn(date)}
			{@const pending = bookings.filter((b) => b.status === 'pending').length}
			{@const booked = bookings.filter((b) => b.status === 'confirmed').length}
			{@const completed = bookings.filter((b) => b.status === 'done').length}
			{@const counts = [pending && pending + ' pending', booked && booked + ' booked', completed && completed + ' completed'].filter(Boolean).join(', ')}
			{@const outside = !date.startsWith(displayedMonth)}
			{@const status = dayStatus(date)}
			{@const closed = status === 'closed' || status === 'blocked'}
			<button
				type="button"
				class="day"
				class:selected={value === date}
				class:closed
				class:is-today={date === today()}
				class:outside
				aria-label={fmtDate(date) + ', ' + (counts || 'no bookings') + (closed ? ', closed' : '')}
				title={closed ? ['Closed', counts].filter(Boolean).join(' · ') : counts || 'No bookings'}
				aria-pressed={value === date}
				aria-current={date === today() ? 'date' : undefined}
				onclick={() => { if (outside) month = date.slice(0, 7); onpick(date); }}
			>
				<time datetime={date}>{Number(date.slice(-2))}</time>
				{#if !outside}
					{#if counts}
						<span class="day-counts" aria-hidden="true">
							{#if pending}<span class="pending">{pending}</span>{/if}
							{#if booked}<span class="confirmed">{booked}</span>{/if}
							{#if completed}<span class="completed">{completed}</span>{/if}
						</span>
					{:else if closed}
						<span class="closed-mark" aria-hidden="true">–</span>
					{/if}
				{/if}
			</button>
		{/each}
	</div>
	<div class="calendar-footer row">
		<p class="small"><b>{fmtDate(value, { weekday: 'short', month: 'short', day: 'numeric' })}</b><span class="muted"> · {bookingsOn(value).length} bookings</span></p>
		<ul class="legend" aria-label="Calendar legend">
			<li class="pending">Pending</li>
			<li class="confirmed">Booked</li>
			<li class="completed">Completed</li>
		</ul>
	</div>
</div>

<style>
	.calendar {
		gap: 0;
		container-type: inline-size;
		overflow: hidden;
		background: var(--panel);
		border: 1px solid var(--line);
		border-radius: 12px;
	}
	.calendar-toolbar { justify-content: space-between; gap: .7rem; padding: .9rem; }
	.calendar-toolbar .eyebrow { font-size: 0.75rem; margin-bottom: 8px; }
	.calendar-toolbar h3 { font-size: 2rem; }
	.calendar-toolbar h3 span { color: var(--muted); font-weight: 600; }
	.calendar-controls { width: 100%; justify-content: space-between; gap: .4rem; }
	.month-arrows { gap: .25rem; }
	.month-arrow, .today-button { min-width: 40px; height: 40px; border: 1px solid var(--line); border-radius: 6px; background: var(--panel); color: var(--text); cursor: pointer; }
	.month-arrow { display: grid; place-items: center; font-size: 1.15rem; }
	.today-button { display: inline-flex; align-items: center; gap: .3rem; padding-inline: 14px; font: 600 0.85rem var(--body); }
	.month-arrow:hover, .today-button:hover { border-color: var(--accent); }
	.month-picker input { min-height: 40px; margin: 0; padding: 6px 10px; font-size: 0.85rem; background: var(--bg); }
	.month-grid { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 3px; padding: 0 .65rem .65rem; }
	.weekday { text-align: center; padding: .4rem 0; font-size: .68rem; font-weight: 700; text-transform: uppercase; }
	.day { min-height: 62px; display: grid; grid-template-rows: auto 1fr; justify-items: center; align-items: end; gap: .22rem; padding: .3rem 2px; color: var(--text); background: transparent; border: 1px solid var(--line); border-radius: 6px; cursor: pointer; }
	.day:hover { background: var(--panel-2); }
	time { display: grid; place-items: center; width: 1.45rem; height: 1.45rem; border: 1px solid transparent; border-radius: 50%; font: 650 .83rem var(--body); }
	.day-counts { display: grid; grid-auto-flow: column; grid-auto-columns: minmax(0, 1fr); gap: 1px; width: 100%; max-width: 3.3rem; font: 750 .65rem/1.3 var(--body); }
	.day-counts > span { text-align: center; border-radius: 3px; }
	.closed-mark { color: var(--muted); line-height: 1; }
	.pending { --status-color: var(--warn); --status-bg: var(--warn-bg); }
	.confirmed { --status-color: var(--accent); --status-bg: var(--bad-bg); }
	.completed { --status-color: var(--ok); --status-bg: var(--ok-bg); }
	.day-counts > span { background: var(--status-bg); color: var(--status-color); }
	.day.closed { background: var(--panel-2); }
	.closed time { color: var(--muted); }
	.day.outside { border-color: transparent; }
	.outside time { color: var(--muted); opacity: .62; }
	.day.selected { background: color-mix(in srgb, var(--accent) 9%, var(--panel)); border-color: var(--accent); }
	.selected time { color: var(--accent-ink); background: var(--accent-fill); }
	.is-today:not(.selected) time { border-color: var(--accent); color: var(--accent); }
	.calendar-footer { justify-content: space-between; padding: .7rem .9rem; border-top: 1px solid var(--line); }
	.legend { display: flex; flex-wrap: wrap; gap: .35rem; width: 100%; margin: 0; padding: 0; list-style: none; }
	.legend li { padding: .24rem .48rem; border-radius: .3rem; background: var(--status-bg, var(--panel-2)); color: var(--status-color, var(--muted)); font-size: .88rem; font-weight: 700; line-height: 1.4; }
	.sr-only { position: absolute; width: 1px; height: 1px; padding: 0; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
	@container (max-width: 370px) {
		.calendar-toolbar, .calendar-footer { padding: .6rem; }
		.calendar-toolbar h3 { font-size: 1.5rem; }
		.month-picker { min-width: 0; }
		.month-grid { padding-inline: .35rem; gap: 2px; }
		.day { min-height: 51px; }
		.day-counts { font-size: .58rem; }
	}
</style>
