<script lang="ts">
 import ActionIcon from '#lib/shared/ActionIcon.svelte';
 import { resolve } from '$app/paths';
 import { addDays, fmtDate, isBookableDate, today } from './dates';
 import { dayStatus } from '../demo/store.svelte';

 let { selected = '', onpick, allows = () => true, statusFor = dayStatus, onmonth }: { selected?: string; onpick?: (date: string) => void; allows?: (date: string) => boolean; statusFor?: (date: string) => string; onmonth?: (from: string, to: string) => void } = $props();
 const currentMonth = today().slice(0, 7);
 const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
 let browsedMonth = $state<string>();
 const month = $derived(browsedMonth ?? (isBookableDate(selected) ? selected.slice(0, 7) : currentMonth));
 const first = $derived(month + '-01');
 const firstDay = $derived(new Date(first + 'T00:00:00Z'));
 const days = $derived(new Date(Date.UTC(firstDay.getUTCFullYear(), firstDay.getUTCMonth() + 1, 0)).getUTCDate());
 const monthDates = $derived(Array.from({ length: days }, (_, i) => addDays(first, i)));
 const leading = $derived((firstDay.getUTCDay() + 6) % 7);
 $effect(() => { onmonth?.(first, addDays(first, days - 1)); });
</script>

<div class="stack calendar" role="group" aria-label="Booking availability">
 <div class="row heading">
  <strong aria-live="polite">{fmtDate(first, { month: 'long', year: 'numeric' })}</strong>
  <div class="row">
   <button type="button" class="cell arrow" aria-label="Previous month" disabled={month === currentMonth} onclick={() => browsedMonth = addDays(first, -1).slice(0, 7)}><ActionIcon name="left" /></button>
   <button type="button" class="cell arrow" aria-label="Next month" onclick={() => browsedMonth = addDays(first, days).slice(0, 7)}><ActionIcon name="right" /></button>
  </div>
 </div>
 <div class="grid">
  {#each weekdays as day}<span class="weekday">{day}</span>{/each}
  {#each Array(leading) as _}<span aria-hidden="true"></span>{/each}
  {#each monthDates as date (date)}
   {@const available = isBookableDate(date) && allows(date) && statusFor(date) === 'open'}
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
 .calendar { border: 1px solid var(--line); border-radius: 12px; background: var(--bg); padding: clamp(8px, 2vw, 16px); }
 .heading { justify-content: space-between; }
 .grid { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 4px; }
 .weekday { text-align: center; color: var(--muted); font-size: .75rem; }
 .cell { display: grid; place-items: center; min-height: 42px; padding: 0; border: 1px solid var(--line); border-radius: 6px; font: inherit; text-decoration: none; }
 .available { background: color-mix(in srgb, var(--ok) 10%, var(--panel)); color: var(--ok); border-color: color-mix(in srgb, var(--ok) 45%, var(--panel)); cursor: pointer; }
 .available:hover { background: color-mix(in srgb, var(--ok) 20%, var(--panel)); }
 .available[aria-pressed='true'] { background: var(--accent-fill); color: var(--accent-ink); border-color: var(--accent); font-weight: 750; }
 .unavailable { color: var(--muted); background: var(--panel-2); }
 .arrow { width: 42px; color: var(--text); background: var(--panel); cursor: pointer; }
 .arrow:disabled { opacity: .45; cursor: default; }
</style>
