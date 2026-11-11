<script lang="ts">
 import AvailabilityCalendar from './AvailabilityCalendar.svelte';
 import { fmtDate, fmtSlot, upcoming } from './dates';
 import { dayStatus, slotsFor } from './store.svelte';
 let { date = $bindable(), slot = $bindable() }: { date: string; slot: string } = $props();
 const dates = upcoming();
 const times = $derived(dates.includes(date) && dayStatus(date) === 'open' ? slotsFor(date) : []);
</script>
<div class="stack">
 <div class="stack">
  <p><strong>Preferred date</strong>{date && times.some(time => time.free) ? ' · ' + fmtDate(date) : ''}</p>
  <AvailabilityCalendar selected={date} onpick={(selected) => { if (date !== selected) slot = ''; date = selected; }} />
 </div>
 {#if times.some(t => t.free)}
  <div class="row" role="group" aria-label="Available times">
   {#each times.filter(t => t.free) as time (time.time)}
    <button type="button" class="time" aria-pressed={slot === time.time} onclick={() => slot = time.time}>{fmtSlot(time.time)}</button>
   {/each}
  </div>
  {#if slot && !times.some(t => t.free && t.time === slot)}<p class="error">Choose one of the available times shown.</p>{/if}
 {:else if date}<p class="error">No times are available. Choose another date.</p>
 {:else}<p class="small muted">Choose a date to see available times.</p>{/if}
 <p class="small muted">Philippine time · Appointment hours are 9 AM to 5 PM</p>
</div>
<style>
 .time { font: inherit; border: 1px solid var(--line); background: var(--panel); color: var(--text); padding: 7px 11px; border-radius: 6px; cursor: pointer; }
 .time:hover, .time[aria-pressed='true'] { background: var(--panel-2); border-color: var(--accent); color: var(--accent); }
</style>
