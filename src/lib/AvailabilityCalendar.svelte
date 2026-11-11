<script lang="ts">
 import { resolve } from '$app/paths';
 import { fmtDate, upcoming } from './dates';
 import { dayStatus } from './store.svelte';

 let { selected = '', onpick }: { selected?: string; onpick?: (date: string) => void } = $props();
 const dates = upcoming();
 const months = [...new Set(dates.map(date => date.slice(0, 7)))];
 const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
 let browsedMonth = $state<number>();
 const month = $derived(browsedMonth ?? Math.max(0, months.indexOf(selected.slice(0, 7))));
 const monthDates = $derived(dates.filter(date => date.startsWith(months[month])));
 const leading = $derived((new Date(monthDates[0] + 'T00:00:00Z').getUTCDay() + 6) % 7);
</script>

<div class="stack calendar" role="group" aria-label="Booking availability">
 <div class="row heading">
  <strong aria-live="polite">{fmtDate(monthDates[0], { month: 'long', year: 'numeric' })}</strong>
  {#if months.length > 1}
   <div class="row">
    <button type="button" class="cell arrow" aria-label="Previous month" disabled={month === 0} onclick={() => browsedMonth = month - 1}>‹</button>
    <button type="button" class="cell arrow" aria-label="Next month" disabled={month === months.length - 1} onclick={() => browsedMonth = month + 1}>›</button>
   </div>
  {/if}
 </div>
 <div class="grid">
  {#each weekdays as day}<span class="weekday">{day}</span>{/each}
  {#each Array(leading) as _}<span aria-hidden="true"></span>{/each}
  {#each monthDates as date (date)}
   {@const available = dayStatus(date) === 'open'}
   {@const day = fmtDate(date, { day: 'numeric' })}
   {#if !available}
    <span class="cell unavailable" aria-label={fmtDate(date) + ', unavailable'}>{day}</span>
   {:else if onpick}
    <button type="button" class="cell available" aria-label={fmtDate(date) + ', available'} aria-pressed={selected === date} onclick={() => onpick?.(date)}>{day}</button>
   {:else}
    <a class="cell available" aria-label={'Book a visit on ' + fmtDate(date)} href={resolve('/book') + '?date=' + date}>{day}</a>
   {/if}
  {/each}
 </div>
 <p class="small muted">Green dates are available. Grey dates are unavailable.</p>
</div>

<style>
 .calendar { border: 1px solid var(--line); border-radius: 8px; padding: clamp(8px, 2vw, 16px); }
 .heading { justify-content: space-between; }
 .grid { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 4px; }
 .weekday { text-align: center; color: var(--muted); font-size: .75rem; }
 .cell { display: grid; place-items: center; min-height: 42px; padding: 0; border: 1px solid var(--line); border-radius: 6px; font: inherit; text-decoration: none; }
 .available { background: #e9f6ed; color: var(--ok); border-color: #9ac7aa; cursor: pointer; }
 .available:hover { background: #d7efdf; }
 .available[aria-pressed='true'] { background: #17643c; color: #fff; border-color: #17643c; }
 .unavailable { color: var(--muted); background: var(--panel-2); }
 .arrow { width: 42px; color: var(--text); background: var(--panel); cursor: pointer; }
 .arrow:disabled { opacity: .45; cursor: default; }
</style>
