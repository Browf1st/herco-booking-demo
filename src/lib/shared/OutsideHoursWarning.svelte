<script lang="ts">
	import { fmtDate } from './dates';
	import { hourText, type OutsideBooking } from './schedule-hours';

	let { bookings, count, more = false, busy = false, onconfirm, onback }: {
		bookings: OutsideBooking[]; count: number; more?: boolean; busy?: boolean; onconfirm: () => void; onback: () => void;
	} = $props();
</script>

<section class="warning stack" role="alert" aria-labelledby="outside-title">
	<h4 id="outside-title">{count} future {count === 1 ? 'booking is' : 'bookings are'} outside the new hours</h4>
	{#if more}<p class="small"><b>More bookings are now outside the new hours.</b></p>{/if}
	<p class="small">Saving never moves or cancels them. Move or cancel them by hand if needed.</p>
	<ul>
		{#each bookings as item (item.reference)}
			<li class="small"><b>{item.reference}</b> · {fmtDate(item.date, { weekday: 'short', month: 'short', day: 'numeric' })} · {hourText(item.hour)}</li>
		{/each}
	</ul>
	{#if count > bookings.length}<p class="small muted">And {count - bookings.length} more.</p>{/if}
	<div class="row">
		<button type="button" class="btn sm" disabled={busy} onclick={onconfirm}>{busy ? 'Saving…' : 'Save anyway'}</button>
		<button type="button" class="btn sm ghost" disabled={busy} onclick={onback}>Go back</button>
	</div>
</section>

<style>
	.warning { gap: .5rem; padding: .7rem; border: 1px solid var(--warn-line); border-radius: 8px; background: var(--warn-bg); color: var(--text); }
	h4 { margin: 0; font-size: .95rem; }
	ul { margin: 0; padding: 0; list-style: none; max-height: 9rem; overflow: auto; }
	li { padding-block: .15rem; }
</style>
