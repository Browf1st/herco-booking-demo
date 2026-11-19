<script lang="ts">
 import DemoPage from './DemoPage.svelte';
 import ServerStaffBookings from '#lib/ServerStaffBookings.svelte';
 import ServerStaffRequests from '#lib/ServerStaffRequests.svelte';
 import { resolve } from '$app/paths';
 import { page } from '$app/state';
 import { onMount } from 'svelte';
 const changes = $derived(page.url.searchParams.get('view') === 'requests');
 let access = $state<{ pages: string[]; actions: string[] }>();
 async function loadAccess() {
  try {
   const response = await fetch(resolve('/api/staff/workspace'));
   access = response.ok ? await response.json() : undefined;
  } catch { access = undefined; }
 }
 onMount(() => { if (import.meta.env.MODE === 'worker') void loadAccess(); });
</script>

{#if import.meta.env.MODE === 'worker'}
 <nav class="wrap row" aria-label="Staff workspace">
  <a class="btn sm ghost" href={resolve('/admin')} aria-current={!changes ? 'page' : undefined}>Bookings</a>
  <a class="btn sm ghost" href={resolve('/admin') + '?view=requests'} aria-current={changes ? 'page' : undefined}>Change requests</a>
  {#if access?.pages.includes('Customers')}<a class="btn sm ghost" href={resolve('/customers')}>Customers</a>{/if}
  {#if access?.pages.includes('HERCO Points')}<a class="btn sm ghost" href={resolve('/staff-points')}>Manage points</a>{/if}
  {#if access?.pages.includes('Inventory')}<a class="btn sm ghost" href={resolve('/inventory')}>Inventory</a>{/if}
  {#if access?.pages.includes('Reports')}<a class="btn sm ghost" href={resolve('/reports')}>Reports</a>{/if}
  {#if access?.pages.includes('Activity log')}<a class="btn sm ghost" href={resolve('/activity-log')}>Activity log</a>{/if}
  {#if access?.pages.includes('Pricing')}<a class="btn sm ghost" href={resolve('/pricing')}>Pricing</a>{/if}
  {#if access?.pages.includes('Staff Access')}<a class="btn sm ghost" href={resolve('/staff-access')}>Staff access</a>{/if}
  {#if access?.pages.includes('Bookings') && access.actions.includes('createBooking')}
   <a class="btn sm ghost" href={resolve('/manual-booking')}>Manual booking</a>
  {/if}
 </nav>
 {#if changes}
  <ServerStaffRequests />
 {:else}
  <ServerStaffBookings onVerified={loadAccess} canComplete={access?.actions.includes('completeBooking') ?? false}
   canAdjustPrices={access?.actions.includes('adjustPrices') ?? false}
   canRequestIntake={access?.pages.includes('Bookings') === true && access.actions.includes('createBooking')} />
 {/if}
{:else}
 <DemoPage />
{/if}
