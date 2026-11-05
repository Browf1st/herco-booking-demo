<script lang="ts">
	import { addDays, fmtDate, isOpenDay, today } from './dates';
	import { bookingsOn, dayStatus } from './store.svelte';

	let { value, onpick }: { value: string; onpick: (date: string) => void } = $props();
	let month = $state('');
	const displayedMonth = $derived(month || value.slice(0, 7));
	const firstDay = $derived(displayedMonth + '-01');
	const leading = $derived((new Date(firstDay + 'T00:00:00Z').getUTCDay() + 6) % 7);
	const days = $derived(new Date(Number(displayedMonth.slice(0, 4)), Number(displayedMonth.slice(5, 7)), 0).getDate());

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

<div class="card stack">
	<div class="row calendar-toolbar">
		<div class="row">
			<button type="button" class="month-arrow" aria-label="Previous month" onclick={() => shiftMonth(-1)}>‹</button>
			<h3>{fmtDate(firstDay, { month: 'long', year: 'numeric' })}</h3>
			<button type="button" class="month-arrow" aria-label="Next month" onclick={() => shiftMonth(1)}>›</button>
		</div>
		<div class="row">
			<label class="month-picker">Jump to month<input type="month" value={displayedMonth} onchange={(e) => { if (/^\d{4}-\d{2}$/.test(e.currentTarget.value)) month = e.currentTarget.value; }} /></label>
			<button type="button" class="btn sm ghost" onclick={goToday}>Today</button>
		</div>
	</div>
	<div class="month-grid" aria-label="Booking calendar">
		{#each ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as weekday}<span class="weekday small muted">{weekday}</span>{/each}
		{#each Array.from({ length: leading }) as _}<span aria-hidden="true"></span>{/each}
		{#each Array.from({ length: days }, (_, i) => addDays(firstDay, i)) as date (date)}
			{@const count = bookingsOn(date).length}
			<button
				type="button"
				class="day"
				class:selected={value === date}
				class:closed={!isOpenDay(date)}
				class:is-today={date === today()}
				aria-label={fmtDate(date) + ', ' + count + ' bookings'}
				aria-pressed={value === date}
				onclick={() => onpick(date)}
			>
				<b>{fmtDate(date, { day: 'numeric' })}</b>
				<span class="small">{count ? count + ' booked' : !isOpenDay(date) ? 'Closed' : dayStatus(date) === 'blocked' ? 'Blocked' : '—'}</span>
			</button>
		{/each}
	</div>
</div>

<style>
	.calendar-toolbar { justify-content: space-between; gap: 16px; }
	.month-arrow { width: 40px; height: 40px; background: var(--panel-2); color: var(--text); border: 1px solid var(--line); border-radius: 6px; font-size: 1.6rem; cursor: pointer; }
	.month-picker { font-size: 0.8rem; }
	.month-picker input { padding: 8px; }
	.month-grid { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 6px; }
	.weekday { text-align: center; }
	.day { min-height: 68px; display: grid; gap: 3px; justify-items: start; padding: 8px; color: var(--text); background: var(--panel-2); border: 1px solid var(--line); border-radius: 6px; cursor: pointer; }
	.day b { font-size: 1.1rem; }
	.day span { color: var(--muted); }
	.closed { background: var(--bg); }
	.selected { border-color: var(--accent); box-shadow: inset 0 -3px var(--accent); }
	.is-today b { color: var(--accent); }
	@media (max-width: 600px) {
		.month-grid { gap: 3px; }
		.day { min-height: 55px; padding: 5px 2px; justify-items: center; }
		.day span { font-size: 0.6rem; }
	}
</style>
