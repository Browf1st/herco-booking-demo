<script lang="ts">
 import AvailabilityCalendar from './AvailabilityCalendar.svelte';
 import { fmtDate, fmtSlot, upcoming } from './dates';
 import { dayStatus, slotsFor } from './store.svelte';
 import { powderDay } from './bookingCatalog';
 let { date = $bindable(), slot = $bindable(), powder = false }: { date: string; slot: string; powder?: boolean } = $props();
 const allows = (day: string) => !powder || powderDay(day);
 const dates = upcoming();
 const times = $derived(dates.includes(date) && allows(date) && dayStatus(date) === 'open' ? slotsFor(date) : []);
</script>
<div class="visit-picker">
 <div class="stack">
  <AvailabilityCalendar selected={date} {allows} onpick={(selected) => { if (date !== selected) slot = ''; date = selected; }} />
 </div>
 <div class="stack">
 <div><strong class="times-title">Available times</strong>
 <p class="small muted">Philippine time · Appointment hours are 9 AM to 5 PM</p></div>
 {#if times.some(t => t.free)}
  <div class="time-grid" role="group" aria-label={'Available times for ' + fmtDate(date)}>
   {#each times.filter(t => t.free) as time (time.time)}
    <button type="button" class="time" aria-pressed={slot === time.time} onclick={() => slot = time.time}>{fmtSlot(time.time)}</button>
   {/each}
  </div>
  {#if slot && !times.some(t => t.free && t.time === slot)}<p class="error">Choose one of the available times shown.</p>{/if}
 {:else if date}<p class="error">No times are available. Choose another date.</p>
 {:else}<p class="small muted">Choose a date to see available times.</p>{/if}
 </div>
</div>
<style>
 .visit-picker { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 235px), 1fr)); align-items: start; gap: 16px; }
 .times-title { text-transform: uppercase; letter-spacing: .04em; font-size: .85rem; }
 .time-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; }
 .time { font: inherit; border: 1px solid var(--line); background: var(--panel); color: var(--text); padding: 9px 6px; border-radius: 9px; cursor: pointer; }
 .time:hover, .time[aria-pressed='true'] { background: var(--panel-2); border-color: var(--accent); color: var(--accent); }
 .time[aria-pressed='true'] { background: color-mix(in srgb, var(--accent) 5%, var(--panel)); box-shadow: inset 0 0 0 1px var(--accent); font-weight: 700; }
</style>
