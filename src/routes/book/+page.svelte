<script lang="ts">
 import { resolve } from '$app/paths';
 import { page } from '$app/state';
 import { tick } from 'svelte';
 import CoatingFields from '#lib/CoatingFields.svelte';
 import VisitPicker from '#lib/VisitPicker.svelte';
 import { account, rememberBooking } from '#lib/account.svelte.ts';
 import { bikes, motorcycleVersions, money, quote, selection, serviceLabel } from '#lib/coating.ts';
 import { sizes, type Size } from '#lib/config.ts';
 import { currentShopTime, fmtDate, fmtSlot, today, upcoming } from '#lib/dates.ts';
 import { book, db, type Booking } from '#lib/store.svelte.ts';

 const query = page.url.searchParams;
 const walkIn = query.get('walk-in') === '1';
 const preferredDate = query.get('date') ?? '';
 let coating = $state(selection(['wheel-colour', 'Powder Coating'].includes(query.get('service') ?? ''), query.get('finish') ?? ''));
 let size = $state<Size>('small');
 const modelGroups = $derived(Object.groupBy(bikes[size], model =>
  model.startsWith('Royal Enfield ') ? 'Royal Enfield' : model.split(' ')[0]
 ));
 let unit = $state('');
 let version = $state('');
 let customVersion = $state('');
 let modelYear = $state<number | undefined>();
 let custom = $state('');
 const baseModel = $derived(unit === 'other' ? custom.trim() : unit);
 const chosenVersion = $derived(version === 'other' ? customVersion.trim() : version);
 const bike = $derived(baseModel && chosenVersion ? baseModel + ' — ' + chosenVersion : baseModel);
 let form = $state({
  name: walkIn ? '' : account.current?.name ?? '', email: walkIn ? '' : account.current?.email ?? '',
  phone: '', plateNumber: '', notes: query.get('notes') ?? '', date: upcoming().includes(preferredDate) ? preferredDate : '', slot: ''
 });
 let signer = $state('');
 let acknowledged = $state(false);
 let immediate = $state(true);
 const estimate = $derived(quote(coating, size, bike, db.pricing));
 let error = $state('');
 let done = $state<Booking>();
 let heading = $state<HTMLHeadingElement>();

 async function submit(event: SubmitEvent) {
  event.preventDefault();
  error = '';
  const name = form.name.trim();
  const phone = form.phone.trim();
  if (!name || !bike || !/^\+?[\d ()-]+$/.test(phone) || phone.replace(/\D/g, '').length < 7) {
   error = 'Enter your name, a valid mobile number, and your motorcycle model.';
   return;
  }
  if (walkIn && (!acknowledged || signer.trim().toLowerCase() !== name.toLowerCase())) {
   error = 'Confirm the intake details and type the customer name to sign the demo form.';
   return;
  }
  try {
   const booking = book({
    ...form, date: walkIn && immediate ? today() : form.date, slot: walkIn && immediate ? currentShopTime() : form.slot,
    name, bike, modelYear, phone, size, selection: $state.snapshot(coating),
    serviceId: coating.ceramic ? 'ceramic' : 'wheel-colour',
    accountId: walkIn ? undefined : account.current?.id,
    walkIn: walkIn ? { signer: signer.trim(), at: new Date().toISOString(), version: 'Demo intake v1', immediate } : undefined
   });
   if (!walkIn && !account.current) rememberBooking(booking.id);
   done = booking;
  } catch (e) {
   error = (e as Error).message;
   return;
  }
  await tick();
  heading?.focus();
 }
</script>

<svelte:head><title>{walkIn ? 'Walk-in intake' : 'Book a visit'} | HERCO</title></svelte:head>

<section class="section wrap stack booking">
 {#if done}
  <p class="eyebrow">{done.id}</p>
  <h1 bind:this={heading} tabindex="-1">{walkIn ? 'Intake saved' : 'Booking submitted'}</h1>
  <p class="muted">This demo request is saved in this browser and awaits shop confirmation.</p>
  <div class="card stack">
   <p><strong>{serviceLabel(done.selection!)}</strong> · {done.bike}{done.modelYear ? ' · Model year ' + done.modelYear : ''}</p>
   <p>{fmtDate(done.date)} at {fmtSlot(done.slot)} (Philippine time)</p>
   <p>Estimated service price <strong>{money(done.estimate!.total)}</strong></p>
  </div>
  <div><a class="btn" href={walkIn ? resolve('/admin?tab=Booking%20history') : resolve('/my-bookings')}>{walkIn ? 'View booking history' : 'View my bookings'}</a></div>
 {:else}
  <h1>{walkIn ? 'Walk-in intake' : 'Book a visit'}</h1>
  <p class="small muted">Demo only. Use sample details. Requests stay in this browser.</p>
  <form class="stack" onsubmit={submit}>
   <fieldset class="card stack booking-panel">
    <legend>Motorcycle and services</legend>
    <div class="cols">
     <label>Motorcycle category
      <select bind:value={size} onchange={() => { unit = ''; version = ''; customVersion = ''; modelYear = undefined; }}>{#each Object.entries(sizes) as [key, label]}<option value={key}>{label}</option>{/each}</select>
     </label>
     <label>Motorcycle model
      <select bind:value={unit} onchange={() => { version = ''; customVersion = ''; modelYear = undefined; }} required>
       <option value="">Choose your unit</option>
       {#each Object.entries(modelGroups) as [brand, models] (brand)}
        <optgroup label={brand}>
         {#each models ?? [] as model (model)}
          <option value={model}>{model}</option>
         {/each}
        </optgroup>
       {/each}
       <option value="other">Other model</option>
      </select>
     </label>
    </div>
    <div class="cols">
     {#if unit === 'other'}<label>Make and model <input bind:value={custom} maxlength="100" required /></label>{/if}
     {#if unit}
      <label>Version or trim (optional)
       <select bind:value={version} onchange={(event) => {
        const listedYear = /^(\d{4}) model$/.exec(event.currentTarget.value)?.[1];
        if (listedYear) modelYear = Number(listedYear);
       }}>
        <option value="">Not sure / skip</option>
        {#each motorcycleVersions(unit) as trim (trim)}<option value={trim}>{trim}</option>{/each}
        <option value="other">Enter a version</option>
       </select>
      </label>
      {#if version === 'other'}<label>Version name<input bind:value={customVersion} maxlength="60" placeholder="e.g. ABS" required /></label>{/if}
     {/if}
     <label>Model year (optional)
      <input type="number" min="1900" max={Number(today().slice(0, 4)) + 1} step="1" placeholder="e.g. 2025" bind:value={modelYear} />
     </label>
    </div>
    <CoatingFields bind:value={coating} {bike} />
    <label>Notes for the shop (optional) <textarea bind:value={form.notes} maxlength="700" rows="2" placeholder="e.g. Please check the brackets for scratches"></textarea></label>
    <div class="estimate">
     <span>Estimated price</span>
     <strong>{coating.ceramic || coating.powderParts.length && coating.powder ? money(estimate.total) : '—'}</strong>
     {#if estimate.discount}<small>{money(estimate.discount)} promo discount</small>{/if}
    </div>
   </fieldset>
   <fieldset class="card stack booking-panel">
    <legend>Contact details</legend>
    <div class="cols">
     <label>Full name <input bind:value={form.name} autocomplete="name" placeholder="e.g. Jamie Reyes" maxlength="70" required /></label>
     <label>Mobile number <input type="tel" bind:value={form.phone} autocomplete="tel" placeholder="e.g. 0917 000 0000" maxlength="20" required /></label>
     <label>Email (optional) <input type="email" bind:value={form.email} autocomplete="email" placeholder="e.g. jamie@example.com" maxlength="254" /></label>
     <label>Plate number (optional) <input bind:value={form.plateNumber} placeholder="e.g. ABC 1234" maxlength="20" /></label>
    </div>
   </fieldset>
   <fieldset class="card stack booking-panel">
    <legend>Preferred visit</legend>
    {#if walkIn}<label class="check"><input type="checkbox" bind:checked={immediate} /> Customer is at the shop now</label>{/if}
    {#if !walkIn || !immediate}<VisitPicker bind:date={form.date} bind:slot={form.slot} />{/if}
    {#if walkIn}
     <p class="small muted">Demo intake acknowledgement. The customer checks the motorcycle and service details above before signing.</p>
     <label class="check"><input type="checkbox" bind:checked={acknowledged} required /> I reviewed the details on this intake form.</label>
     <label>Customer signature (type full name for this demo) <input bind:value={signer} required /></label>
    {/if}
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    <div><button class="btn">{walkIn ? 'Save walk-in intake' : 'Submit booking'}</button></div>
   </fieldset>
  </form>
 {/if}
</section>

<style>
 .booking { max-width: 860px; }
 h1 { font-size: clamp(2.6rem, 8vw, 4.2rem); }
 fieldset { min-inline-size: 0; margin: 0; }
 legend { padding-inline: 6px; font-weight: 750; font-size: 1.2rem; }
 .booking-panel {
  padding: clamp(16px, 3vw, 28px);
  gap: 18px;
  border-radius: 12px;
 }
 .booking-panel > .cols {
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 235px), 1fr));
 }
 .booking-panel label { min-width: 0; }
 .booking-panel select { min-width: 0; }
 .estimate {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 6px 16px;
  padding: 12px 16px;
  background: var(--panel-2);
  border-radius: 8px;
 }
 .estimate strong { margin-inline-start: auto; font-size: 1.25rem; }
 .estimate small { flex-basis: 100%; text-align: end; color: var(--muted); }
 .check { display: flex; align-items: center; gap: 8px; }
</style>
