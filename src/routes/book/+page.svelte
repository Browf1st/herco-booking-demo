<script lang="ts">
 import { resolve } from '$app/paths';
 import { page } from '$app/state';
 import { tick } from 'svelte';
 import BookingCatalog from '#lib/BookingCatalog.svelte';
 import { ceramicModels } from '#lib/bookingCatalog.ts';
 import VisitPicker from '#lib/VisitPicker.svelte';
 import { account, rememberBooking } from '#lib/account.svelte.ts';
 import { estimatePrice, linePrice, money, quote, selection, serviceLabel } from '#lib/coating.ts';
 import { type Size } from '#lib/config.ts';
 import { currentShopTime, fmtDate, fmtSlot, today, upcoming } from '#lib/dates.ts';
 import { book, db, type Booking } from '#lib/store.svelte.ts';

 const query = page.url.searchParams;
 const walkIn = query.get('walk-in') === '1';
 const preferredDate = query.get('date') ?? '';
 const requestedService = query.get('service');
 let coating = $state({
  ...selection(['wheel-colour', 'Powder Coating'].includes(requestedService ?? ''), query.get('finish') ?? ''),
  ceramic: requestedService !== null && !['wheel-colour', 'Powder Coating'].includes(requestedService),
  catalog: { ceramicAddons: [] as string[], wheelType: '', prismatic: false, wheelExtras: [] as string[], bigBike: false, otherBigBike: false }
 });
 let unit = $state('');
 let modelYear = $state<number>();
 const pcxYears = [2026, 2025, 2024, 2023, 2022, 2021, 2020, 2019, 2018];
 let powderBike = $state('');
 let custom = $state('');
 const manualModel = $derived(unit === 'other' || unit === 'other-big-bike');
 const size = $derived<Size>(coating.catalog.bigBike ? 'large' : 'small');
 const bike = $derived(coating.ceramic ? (manualModel ? custom.trim() : unit) : powderBike.trim());
 function selectMotorcycle(model: string) {
  modelYear = undefined;
  custom = '';
  coating.catalog.otherBigBike = model === 'other-big-bike';
  coating.catalog.bigBike = coating.catalog.otherBigBike || model === 'Kawasaki Dominar 400';
 }
 const modelLabels: Record<string, string> = {
  'Yamaha Mio Gravis': 'Gravis', 'Yamaha Mio Soul': 'Mio Soul', 'Honda Click125': 'Click v1–v3',
  'Yamaha Sniper 155': 'Sniper', 'Yamaha Mio Gear': 'Mio Gear', 'Yamaha NMAX': 'NMAX v1–v3',
  'Yamaha Aerox': 'Aerox v1–v3', 'Suzuki Raider R150': 'Raider', 'Suzuki Burgman Street': 'Burgman',
  'Honda Wave RSX': 'Honda Wave', 'Honda Rebel': 'Rebel', 'Honda AirBlade160': 'Airblade',
  'Honda ADV160': 'ADV RoadSync V1, V2, V3', 'Honda Giorno+': 'Giorno', 'Yamaha Mio Fazzio': 'Fazzio',
  'Honda PCX160': 'PCX', 'Kawasaki Dominar 400': 'Dominar 400', 'Honda Click160': 'Click 160',
  'Kymco Like 150i': 'Kymco Like', 'Suzuki Gixxer 155': 'Gixxer', 'Vespa Primavera 150': 'Vespa',
  'Yamaha XMAX': 'XMAX'
 };
 const groupedAliases = ['Honda ADV150', 'Honda PCX150', 'Suzuki Gixxer 250'];
 const tierNames: Record<string, string> = { 1799: 'Standard / Underbone', 1999: 'Mid-Range / Maxi', 2499: 'Big Bike / Premium' };
 const tierDescriptions: Record<string, string> = { 1799: 'Scooters and underbones', 1999: 'Maxi scooters and naked bikes', 2499: 'Vespa, 400 cc and up, and more' };
 const tiers = Object.entries(ceramicModels);
 let form = $state({
  name: walkIn ? '' : account.current?.name ?? '', email: walkIn ? '' : account.current?.email ?? '',
  phone: walkIn ? '' : account.current?.phone ?? '', plateNumber: '', notes: query.get('notes') ?? '', date: upcoming().includes(preferredDate) ? preferredDate : '', slot: ''
 });
 let signer = $state('');
 let acknowledged = $state(false);
 let immediate = $state(true);
 const isPcx = $derived(coating.ceramic && /^Honda PCX/i.test(bike));
 const estimate = $derived(quote(coating, size, bike, db.pricing, [], isPcx ? modelYear : undefined));
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
    name, bike, modelYear: isPcx ? modelYear : undefined, phone, email: form.email.trim(), size, selection: $state.snapshot(coating),
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
   <p>Estimated service price <strong>{estimatePrice(done.estimate!)}</strong></p>
  </div>
  <div><a class="btn" href={walkIn ? resolve('/admin?tab=Booking%20history') : resolve('/my-bookings')}>{walkIn ? 'View booking history' : 'View my bookings'}</a></div>
 {:else}
  <h1>{walkIn ? 'Walk-in intake' : 'Book a visit'}</h1>
  <p class="small muted">Demo only. Use sample details. Requests stay in this browser.</p>
  <form class="booking-layout" onsubmit={submit}>
   <div class="stack booking-steps">
   <fieldset class="card stack booking-panel">
    <legend><span>1</span> Choose a service</legend>
    <div class="cols">
     <label class="service-choice"><input type="checkbox" bind:checked={coating.ceramic} /><strong>Ceramic coating</strong><span class="small muted">Paint protection and detailing</span></label>
     <label class="service-choice"><input type="checkbox" bind:checked={coating.powder} /><strong>Powder coating</strong><span class="small muted">Color and finish for mags and small parts</span></label>
    </div>
   </fieldset>
   {#if coating.ceramic || coating.powder}
   <fieldset class="card stack booking-panel">
    <legend><span>2</span> Motorcycle and service options</legend>
    {#if coating.ceramic}
    <div class="stack models" role="group" aria-label="Motorcycle models">
     <p class="small muted">Prices shown are for ceramic coating.</p>
     <div class="model-groups">
      {#each tiers as [price, models], index}
       <div class="model-group" class:selected={models.includes(unit) || (price === '2499' && unit === 'other-big-bike')}>
        <div class="tier-heading">
         <div class="tier-label">Tier {index + 1}<span class="tier-indicator" aria-hidden="true"></span></div>
         <strong>{tierNames[price]}</strong>
         <p class="small muted">{tierDescriptions[price]}</p>
         <div class="tier-price"><span class="small muted">From</span> <strong>{money(Number(price))}</strong></div>
        </div>
        <div class="model-options">
       {#each models.filter(model => !groupedAliases.includes(model)) as model}
        <label class="model"><input type="radio" name="motorcycle" value={model} bind:group={unit} onchange={() => selectMotorcycle(model)} aria-label={(modelLabels[model] ?? model) + ', ceramic coating ' + money(Number(price))} /> {modelLabels[model] ?? model}</label>
       {/each}
        {#if price === '2499'}
         <label class="model"><input type="radio" name="motorcycle" value="other-big-bike" bind:group={unit} onchange={() => selectMotorcycle('other-big-bike')} /> Other big bike (400 cc and up)</label>
        {/if}
        </div>
       </div>
      {/each}
     </div>
     <label class="model"><input type="radio" name="motorcycle" value="other" bind:group={unit} onchange={() => selectMotorcycle('other')} /> Motorcycle not listed</label>
     {#if manualModel}
      <label>Brand and model
       <input bind:value={custom} placeholder={unit === 'other-big-bike' ? 'e.g. Ducati Monster' : 'e.g. Yamaha MT-15'} maxlength="100" required />
      </label>
     {/if}
    </div>
    {/if}
    {#if isPcx}
     <label>PCX model year
      <select bind:value={modelYear} required>
       <option value={undefined} disabled>Select model year</option>
       {#each pcxYears as year}<option value={year}>{year}</option>{/each}
      </select>
     </label>
    {/if}
    {#if bike || !coating.ceramic}
     <BookingCatalog bind:value={coating} {bike} year={isPcx ? modelYear : undefined} serviceControls={false} --ceramic-package-bg="#fdfafa">
      {#snippet powderDetails()}
       {#if !coating.ceramic}
        <label>Motorcycle brand and model <input bind:value={powderBike} placeholder="e.g. Yamaha Sniper 155" maxlength="100" required /></label>
       {/if}
      {/snippet}
     </BookingCatalog>
    {/if}
    <label>Notes for the shop (optional) <textarea bind:value={form.notes} maxlength="700" rows="2" placeholder="e.g. Please check the brackets for scratches"></textarea></label>

   </fieldset>
   {#if bike}
   <fieldset class="card stack booking-panel contact-panel">
    <legend><span>3</span> Contact details and vehicle plate</legend>
    <div class="cols">
     <label>Full name <input bind:value={form.name} autocomplete="name" placeholder="e.g. Jamie Reyes" maxlength="70" required /></label>
     <label>Mobile number <input type="tel" bind:value={form.phone} autocomplete="tel" placeholder="e.g. 0917 000 0000" maxlength="20" required /></label>
     <label>
      <span>Email <span class:required-label={!walkIn}>{walkIn ? '(optional)' : '(required)'}</span></span>
      <input type="email" bind:value={form.email} autocomplete="email" placeholder="e.g. jamie@example.com" maxlength="254" required={!walkIn} aria-describedby={walkIn ? undefined : 'booking-email-help'} />
      {#if !walkIn}<span id="booking-email-help" class="small muted email-help">Used for booking reminders.</span>{/if}
     </label>
     <label>Plate number (optional) <input bind:value={form.plateNumber} placeholder="e.g. ABC 1234" maxlength="20" /></label>
    </div>
   </fieldset>
   <fieldset class="card stack booking-panel">
    <legend><span>4</span> Preferred date and time</legend>
    {#if walkIn}<label class="check"><input type="checkbox" bind:checked={immediate} /> Customer is at the shop now</label>{/if}
    {#if !walkIn || !immediate}<VisitPicker bind:date={form.date} bind:slot={form.slot} powder={coating.powder} />{/if}
    {#if walkIn}
     <p class="small muted">Demo intake acknowledgement. The customer checks the motorcycle and service details above before signing.</p>
     <label class="check"><input type="checkbox" bind:checked={acknowledged} required /> I reviewed the details on this intake form.</label>
     <label>Customer signature (type full name for this demo) <input bind:value={signer} required /></label>
    {/if}
   </fieldset>
   {/if}
   {/if}
   </div>
   <aside class="card stack booking-cart" aria-label="Booking summary">
    <div class="stack" aria-live="polite">
     <h2 class="cart-title">Booking cart</h2>
     {#if bike}<div class="cart-line"><span>Motorcycle</span><strong>{bike}</strong></div>{/if}
     {#if form.date && form.slot}<div class="cart-line"><span>Preferred visit</span><strong>{fmtDate(form.date)} · {fmtSlot(form.slot)}</strong></div>{/if}
     {#each estimate.lines ?? [] as line (line.label)}
      <div class="cart-line"><span>{line.label}</span><strong>{linePrice(line)}</strong></div>
     {:else}
      <p>Choose a service to add it to your booking.</p>
     {/each}
     {#if estimate.lines?.length}
      {#if estimate.discount}<div class="cart-line"><span>Estimated promo savings</span><strong>{money(estimate.discount)}</strong></div>{/if}
      <div class="cart-line cart-total"><span>Estimated total</span><strong>{estimatePrice(estimate)}</strong></div>
      <p class="small muted">Your estimate may change after an in-shop inspection. The shop will confirm any price changes with you before starting the work.</p>
     {/if}
    </div>
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    <button class="btn" disabled={!bike || (!coating.ceramic && !coating.powder)}>{walkIn ? 'Save walk-in intake' : 'Submit booking'}</button>
   </aside>
  </form>
 {/if}
</section>

<style>
 .booking { max-width: 1280px; color-scheme: light; --bg: #f8fafc; --panel-2: #f1f5f9; --line: #cbd5e1; --text: #0f172a; --muted: #475569; --accent: #b91c1c; background: var(--bg); color: var(--text); }

 .booking-layout { display: grid; gap: 20px; align-items: start; }
 .booking-steps { min-width: 0; gap: 24px; }
 .booking-cart { border-top: 4px solid var(--accent); border-radius: 12px; padding: 20px; box-shadow: 0 4px 12px #0f172a14; }
 .booking-cart .btn { width: 100%; clip-path: none; border-radius: 8px; }
 @media (min-width: 960px) {
  .booking-layout { grid-template-columns: minmax(0, 2fr) minmax(280px, 1fr); gap: 24px; }
  .booking-cart { position: sticky; top: 80px; max-height: calc(100vh - 100px); overflow: auto; }
 }
 legend span { display: inline-grid; place-items: center; width: 1.65em; aspect-ratio: 1; margin-inline-end: 6px; border-radius: 50%; background: var(--accent); color: var(--accent-ink); font-size: .82em; }
 h1 { font-family: var(--body); font-size: clamp(2rem, 5vw, 3.25rem); font-weight: 900; font-style: italic; letter-spacing: -.03em; }
 fieldset { min-inline-size: 0; margin: 0; }
 legend { padding-inline: 6px; font-weight: 750; font-size: 1.2rem; }
 .booking-panel {
  padding: clamp(16px, 3vw, 28px);
  gap: 18px;
  border-radius: 12px;
  box-shadow: 0 1px 3px #0f172a14;
 }
 .booking-panel > .cols {
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 235px), 1fr));
 }
 .booking-panel label { min-width: 0; }
 .models { min-inline-size: 0; }
 .model-groups { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 175px), 1fr)); align-items: start; gap: 10px; }
 .model-group { display: grid; gap: 4px; padding: 12px; background: var(--bg); border: 1px solid var(--line); border-radius: 12px; }
 .model-group.selected { border-color: var(--accent); box-shadow: inset 0 0 0 1px var(--accent); }
 .service-choice { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 4px 12px; padding: 16px; border: 1px solid var(--line); border-radius: 12px; background: var(--bg); color: var(--text); cursor: pointer; }
 .service-choice input { grid-area: 1 / 2; align-self: center; appearance: none; width: 1rem; height: 1rem; margin: 0; border: 1px solid var(--line); border-radius: 50%; background: var(--panel); }
 .service-choice input:checked { border: .3rem solid var(--accent); }
 .service-choice strong { grid-area: 1 / 1; }
 .service-choice span { grid-column: 1 / -1; }
 .service-choice:hover { background: var(--panel-2); }
 .service-choice:has(:checked) { border-color: var(--accent); background: color-mix(in srgb, var(--accent) 6%, var(--panel)); box-shadow: inset 0 0 0 1px var(--accent); }
 .service-choice:has(:focus-visible) { outline: 2px solid var(--accent); outline-offset: 2px; }
 .tier-heading { display: grid; gap: 6px; padding: 4px; }
 .tier-label { display: flex; justify-content: space-between; align-items: center; color: var(--muted); font-size: .75rem; font-weight: 750; letter-spacing: .06em; text-transform: uppercase; }
 .tier-indicator { display: grid; place-items: center; width: 16px; height: 16px; border: 1px solid var(--line); border-radius: 50%; }
 .selected .tier-indicator { border-color: var(--accent); background: var(--accent); }
 .selected .tier-indicator::after { content: ''; width: 6px; height: 6px; border-radius: 50%; background: var(--accent-ink); }
 .tier-price { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px; border-top: 1px solid var(--line); margin-top: 4px; padding-top: 8px; }
 .tier-price strong { font-size: 1.25rem; }
 .model-options { display: grid; gap: 2px; border-top: 1px solid var(--line); margin-top: 6px; padding-top: 6px; }
 .model { display: flex; align-items: center; gap: 8px; min-height: 38px; padding: 4px 7px; border-radius: 6px; color: var(--text); font-size: .9rem; cursor: pointer; }
 .model input { flex: none; width: 1rem; height: 1rem; margin: 0; accent-color: var(--accent); }
 .model:hover, .model:has(:checked) { background: var(--panel-2); }
 .model:has(:checked) { box-shadow: inset 0 0 0 1px var(--accent); }
 .model:has(:focus-visible) { outline: 2px solid var(--accent); outline-offset: 2px; }
 .cart-title { padding-bottom: 12px; border-bottom: 1px solid var(--line); font-family: var(--body); font-size: 1.15rem; font-weight: 900; font-style: italic; letter-spacing: -.03em; }
 .cart-line { display: flex; justify-content: space-between; gap: 10px; }
 .cart-line strong { text-align: right; }
 .cart-total { border-top: 1px solid var(--line); padding-top: 10px; }
 .check { display: flex; align-items: center; gap: 8px; }
 .contact-panel > .cols { grid-template-columns: repeat(auto-fit, minmax(min(100%, 190px), 1fr)); }
 .contact-panel label { align-content: start; font-weight: 600; }
 .contact-panel input, .booking-panel textarea { background: var(--panel); border-radius: 10px; font-weight: 400; }
 .required-label { color: var(--accent); font-weight: 400; }
 .email-help { font-weight: 400; }
</style>
