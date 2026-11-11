<script lang="ts">
 import { resolve } from '$app/paths';
 import { account } from '#lib/account.svelte.ts';
 import CustomerBookingHistory from '#lib/CustomerBookingHistory.svelte';
</script>
<svelte:head><title>My bookings | HERCO</title></svelte:head>
<section class="section wrap stack">
 <h1>My bookings</h1>
 <p class="muted">See your service status and request changes. The shop reviews cancellation and rescheduling requests.</p>
 <div class="row"><a class="btn sm" href={resolve('/book')}>New booking</a><a class="btn sm ghost" href={resolve('/account')}>{account.current ? 'Demo account' : 'Demo login / signup'}</a></div>
 <CustomerBookingHistory />
</section>
