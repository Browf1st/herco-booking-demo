<script lang="ts">
 import ActionIcon from '#lib/ActionIcon.svelte';
 import { resolve } from '$app/paths';
 import { goto } from '$app/navigation';
 import { page } from '$app/state';
 import { tick } from 'svelte';
 import BookingCatalog from '#lib/BookingCatalog.svelte';
 import { ceramicModels, ceramicTierNames, createCatalogOptions, defaultCeramicCatalogPricing } from '#lib/bookingCatalog.ts';
 import VisitPicker from '#lib/VisitPicker.svelte';
 import { account, rememberBooking } from '#lib/account.svelte.ts';
 import { applyServicePriceAdjustments, estimatePrice, linePrice, money, olderPowderParts, quote, selection, serviceLabel } from '#lib/coating.ts';
 import { adminPath, bookingSections } from '#lib/adminNavigation.ts';
 import { type Size } from '#lib/config.ts';
 import { currentShopTime, fmtDate, fmtSlot, isBookableDate, today } from '#lib/dates.ts';
 import { book, catalogSelectionOf, db, editCoating, estimateServiceEdit, type Booking } from '#lib/store.svelte.ts';

 const query = page.url.searchParams;
 const editId = query.get('edit');
 const editedBooking = editId ? db.bookings.find(booking => booking.id === editId) : undefined;
 const editing = Boolean(editId);
 const canEdit = $derived(!editing || editedBooking?.status === 'pending' || editedBooking?.status === 'confirmed');
 const returnSection = bookingSections.find(section => section === query.get('return')) ?? 'Booking history';
 const returnToBooking = resolve(adminPath('Booking', query.get('view') === 'owner', returnSection));
 const manual = query.get('manual') === '1';
 let walkIn = $state(!editing && query.get('walk-in') === '1');
 const preferredDate = query.get('date') ?? '';
 const requestedService = query.get('service');
 const editSelection = editedBooking ? catalogSelectionOf(editedBooking) : undefined;
 let coating = $state(editSelection ?? {
  ...selection(['wheel-colour', 'Powder Coating'].includes(requestedService ?? ''), query.get('finish') ?? ''),
  ceramic: requestedService !== null && !['wheel-colour', 'Powder Coating'].includes(requestedService),
  catalog: createCatalogOptions()
 });
 const groupedAliases = ['Honda ADV150', 'Honda PCX150', 'Suzuki Gixxer 250'];
 const savedModel = editedBooking?.bike.split(' — ')[0] ?? '';
 const initialUnit = !editedBooking ? '' : editSelection?.catalog.otherBigBike ? 'other-big-bike'
  : Object.values(ceramicModels).flat().includes(savedModel) && !groupedAliases.includes(savedModel) ? savedModel : 'other';
 let unit = $state(initialUnit);
 let modelYear = $state<number | undefined>(editedBooking?.modelYear);
 const pcxYears = [2026, 2025, 2024, 2023, 2022, 2021, 2020, 2019, 2018];
 let powderBike = $state(editedBooking?.bike ?? '');
 let custom = $state(initialUnit.startsWith('other') ? editedBooking?.bike ?? '' : '');
 const manualModel = $derived(unit === 'other' || unit === 'other-big-bike');
 const bike = $derived(coating.ceramic ? (manualModel ? custom.trim() : unit === initialUnit && editedBooking ? editedBooking.bike : unit) : powderBike.trim());
 const size = $derived<Size | undefined>(editedBooking && bike === editedBooking.bike ? editedBooking.size : coating.catalog.bigBike ? 'large' : 'small');
 const olderParts = olderPowderParts(editSelection?.powderParts ?? []);
 function selectMotorcycle(model: string) {
  modelYear = undefined;
  custom = '';
  adjustments = {};
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
 const tierDescriptions: Record<string, string> = { 1799: 'Scooters and underbones', 1999: 'Maxi scooters and naked bikes', 2499: 'Vespa, 400 cc and up, and more' };
 const tiers = Object.entries(ceramicModels);
 const ceramicPricing = $derived(db.pricing.ceramicCatalog ?? defaultCeramicCatalogPricing);
 let form = $state({
  name: editedBooking?.name ?? (manual ? '' : account.current?.name ?? ''), email: editedBooking?.email ?? (manual ? '' : account.current?.email ?? ''),
  phone: editedBooking?.phone ?? (manual ? '' : account.current?.phone ?? ''), plateNumber: editedBooking?.plateNumber ?? '',
  notes: editedBooking?.notes ?? query.get('notes') ?? '', date: editedBooking?.date ?? (isBookableDate(preferredDate) ? preferredDate : ''), slot: editedBooking?.slot ?? ''
 });
 let signer = $state('');
 let acknowledged = $state(false);
 let immediate = $state(manual);
 const isPcx = $derived(coating.ceramic && /^Honda PCX/i.test(bike));
 let adjustments = $state<Record<string, number | undefined>>({});
 const vehicle = $derived({ bike, size, modelYear: isPcx || (editedBooking && bike === editedBooking.bike) ? modelYear : undefined });
 const baseEstimate = $derived(editedBooking ? estimateServiceEdit(editedBooking, coating, vehicle) : quote(coating, size ?? 'small', bike, db.pricing, [], vehicle.modelYear));
 const estimate = $derived(applyServicePriceAdjustments(baseEstimate, Object.fromEntries(Object.entries(adjustments).filter(([, value]) => value !== undefined && value >= 0 && Number.isSafeInteger(Math.round(value * 100))))));
 let error = $state('');
 let done = $state<Booking>();
 let reviewDialog: HTMLDialogElement;
 let reviewError = $state('');
 let reviewVisit = $state({ date: '', slot: '' });
 let heading = $state<HTMLHeadingElement>();

 async function submit(event: SubmitEvent) {
  event.preventDefault();
  error = '';
  if (editedBooking) {
   try {
    editCoating(editedBooking, $state.snapshot(coating), 'Demo admin', { ...vehicle, notes: form.notes.trim(), adjustments: $state.snapshot(adjustments) });
    await goto(returnToBooking);
   } catch (e) { error = (e as Error).message; }
   return;
  }
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
  reviewVisit = { date: walkIn && immediate ? today() : form.date, slot: walkIn && immediate ? currentShopTime() : form.slot };
  if (!reviewVisit.date || !reviewVisit.slot) {
   error = 'Choose an appointment date and time.';
   return;
  }
  reviewError = '';
  reviewDialog.showModal();
 }

 async function confirmBooking() {
  if (done || !reviewDialog.open) return;
  reviewError = '';
  try {
   const booking = book({
    ...form, ...reviewVisit,
    name: form.name.trim(), bike, modelYear: isPcx ? modelYear : undefined, phone: form.phone.trim(), email: form.email.trim(), size, selection: $state.snapshot(coating),
    serviceId: coating.ceramic ? 'ceramic' : 'wheel-colour',
    accountId: manual ? undefined : account.current?.id,
    bookedByStaff: manual,
    walkIn: walkIn ? { signer: signer.trim(), at: new Date().toISOString(), version: 'Demo intake v1', immediate } : undefined
   });
   if (!manual && !account.current) rememberBooking(booking.id);
   reviewDialog.close();
   done = booking;
  } catch (e) {
   reviewError = (e as Error).message;
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
  <div><a class="btn" href={manual ? resolve(query.get('view') === 'owner' ? '/admin?tab=Booking%20history&view=owner' : '/admin?tab=Booking%20history') : resolve('/my-bookings')}><ActionIcon name="history" />{manual ? 'View booking history' : 'View my bookings'}</a></div>
 {:else if !canEdit}
  <h1>Edit services</h1>
  <p class="muted">This booking is no longer available to edit.</p>
  <div><a class="btn ghost" href={returnToBooking}><ActionIcon name="back" /> Back to bookings</a></div>
 {:else}
  <h1>{walkIn ? 'Walk-in intake' : manual ? 'Manual booking' : 'Book a visit'}</h1>
  {#if !editing}
   <label class="booking-source">Booking source
    <select bind:value={walkIn}><option value={false}>Online</option><option value={true}>Walk-in</option></select>
   </label>
  {/if}
  <p class="small muted">{editedBooking ? 'Editing services for ' + editedBooking.id : 'Demo only. Use sample details. Requests stay in this browser.'}</p>
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
       {@const tier = Number(price) as keyof typeof ceramicModels}
       <div class="model-group" class:selected={models.includes(unit) || (price === '2499' && unit === 'other-big-bike')}>
        <div class="tier-heading">
         <div class="tier-label">Tier {index + 1}<span class="tier-indicator" aria-hidden="true"></span></div>
         <strong>{ceramicTierNames[tier]}</strong>
         <p class="small muted">{tierDescriptions[price]}</p>
         <div class="tier-price"><span class="small muted">From</span> <strong>{money(ceramicPricing.tiers[tier])}</strong></div>
        </div>
        <div class="model-options">
       {#each models.filter(model => !groupedAliases.includes(model)) as model}
        <label class="model"><input type="radio" name="motorcycle" value={model} bind:group={unit} onchange={() => selectMotorcycle(model)} aria-label={(modelLabels[model] ?? model) + ', ceramic coating ' + money(ceramicPricing.tiers[tier])} /> {modelLabels[model] ?? model}</label>
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
      <select bind:value={modelYear} required={!editing}>
       <option value={undefined} disabled={!editing}>{editing ? 'Not recorded' : 'Select model year'}</option>
       {#each pcxYears as year}<option value={year}>{year}</option>{/each}
      </select>
     </label>
    {/if}
    {#if bike || !coating.ceramic}
     <BookingCatalog bind:value={coating} {bike} year={isPcx ? modelYear : undefined} serviceControls={false} {olderParts}>
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
     <label>Full name <input bind:value={form.name} autocomplete="name" placeholder="e.g. Jamie Reyes" maxlength="70" readonly={editing} required={!editing} /></label>
     <label>Mobile number <input type="tel" bind:value={form.phone} autocomplete="tel" placeholder="e.g. 0917 000 0000" maxlength="20" readonly={editing} required={!editing} /></label>
     <label>
      <span>Email {#if !editing}<span class:required-label={!walkIn}>{walkIn ? '(optional)' : '(required)'}</span>{/if}</span>
      <input type="email" bind:value={form.email} autocomplete="email" placeholder="e.g. jamie@example.com" maxlength="254" readonly={editing} required={!walkIn && !editing} aria-describedby={walkIn || editing ? undefined : 'booking-email-help'} />
      {#if !walkIn && !editing}<span id="booking-email-help" class="small muted email-help">Used for booking reminders.</span>{/if}
     </label>
     <label>Plate number (optional) <input bind:value={form.plateNumber} placeholder="e.g. ABC 1234" maxlength="20" readonly={editing} /></label>
    </div>
   </fieldset>
   <fieldset class="card stack booking-panel">
    <legend><span>4</span> {editing ? 'Scheduled date and time' : 'Preferred date and time'}</legend>
    {#if editing}
     <p>{fmtDate(form.date)} · {fmtSlot(form.slot)} (Philippine time)</p>
    {:else}
    {#if walkIn && manual}<label class="check"><input type="checkbox" bind:checked={immediate} /> Customer is at the shop now</label>{/if}
    {#if !walkIn || !immediate}<VisitPicker bind:date={form.date} bind:slot={form.slot} powder={coating.powder} />{/if}
    {#if walkIn}
     <p class="small muted">Demo intake acknowledgement. The customer checks the motorcycle and service details above before signing.</p>
     <label class="check"><input type="checkbox" bind:checked={acknowledged} required /> I reviewed the details on this intake form.</label>
     <label>Customer signature (type full name for this demo) <input bind:value={signer} required /></label>
    {/if}
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
      {#if editing}
       <label class="price-adjustment">
        Adjusted price (₱)
        <input type="number" min="0" step="0.01" placeholder="Use current price" aria-label={'Adjusted price for ' + line.label} bind:value={adjustments[line.label]} />
       </label>
      {/if}
     {:else}
      <p>Choose a service to add it to your booking.</p>
     {/each}
     {#if estimate.lines?.length}
      {#if estimate.discount}<div class="cart-line"><span>Estimated promo savings</span><strong>{money(estimate.discount)}</strong></div>{/if}
      <div class="cart-line cart-total"><span>Estimated total</span><strong>{estimatePrice(estimate)}</strong></div>
      {#if editing}<p class="small muted">Leave a field blank to keep its current price. An adjusted price is the amount for that item after any discount.</p>
      {:else}<p class="small muted">Your estimate may change after an in-shop inspection. The shop will confirm any price changes with you before starting the work.</p>{/if}
     {/if}
    </div>
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    <button class="btn" disabled={!bike || (!coating.ceramic && !coating.powder)}><ActionIcon name={walkIn || editing ? "save" : "send"} />{editing ? 'Save service changes' : walkIn ? 'Save walk-in intake' : 'Submit booking'}</button>
    {#if editing}<a class="btn sm ghost" href={returnToBooking}><ActionIcon name="back" />Cancel edit</a>{/if}
   </aside>
  </form>
 {/if}
</section>

<dialog bind:this={reviewDialog} aria-labelledby="review-title" class="booking-review">
 <div class="stack">
  <h2 id="review-title">Review booking</h2>
  <dl class="review-facts">
   <div><dt>Booking source</dt><dd>{walkIn ? 'Walk-in' : 'Online'}</dd></div>
   <div><dt>Appointment · Philippine time</dt><dd>{reviewVisit.date ? fmtDate(reviewVisit.date, {month:'long', day:'numeric', year:'numeric'}) : ''} · {reviewVisit.slot ? fmtSlot(reviewVisit.slot) : ''}</dd></div>
   <div><dt>Customer</dt><dd>{form.name.trim()}</dd></div>
   <div><dt>Mobile</dt><dd>{form.phone.trim()}</dd></div>
   <div><dt>Email</dt><dd>{form.email.trim() || 'Not provided'}</dd></div>
   <div><dt>Motorcycle</dt><dd>{bike}{isPcx && modelYear ? ' · ' + modelYear : ''}</dd></div>
   <div><dt>Plate number</dt><dd>{form.plateNumber.trim() || 'Not provided'}</dd></div>
   {#if walkIn}<div><dt>Intake signed by</dt><dd>{signer.trim()}</dd></div>{/if}
   <div class="review-notes"><dt>Notes for the shop</dt><dd>{form.notes.trim() || 'None'}</dd></div>
  </dl>
  <section class="stack" aria-label="Services and estimated prices">
   <h3>Services and estimate</h3>
   <p>{serviceLabel(coating)}{coating.powder && coating.finish ? ' · ' + coating.finish : ''}</p>
   {#each estimate.lines ?? [] as line}<div class="cart-line"><span>{line.label}</span><strong>{linePrice(line)}</strong></div>{/each}
   {#if estimate.discount}<div class="cart-line"><span>Promo savings</span><strong>{money(estimate.discount)}</strong></div>{/if}
   <div class="cart-line cart-total"><span>Estimated total</span><strong>{estimatePrice(estimate)}</strong></div>
  </section>
  {#if reviewError}<p class="error" role="alert">{reviewError}</p>{/if}
  <div class="row"><button type="button" class="btn sm ghost" onclick={() => reviewDialog.close()}>Back to edit</button><button type="button" class="btn sm" onclick={confirmBooking}><ActionIcon name="check" />Confirm and submit</button></div>
 </div>
</dialog>

<style>
 .booking-review { width: min(680px, calc(100% - 24px)); max-height: 88dvh; padding: clamp(16px, 4vw, 28px); border: 1px solid var(--line); border-radius: 12px; background: var(--panel); color: var(--text); }
 .booking-review::backdrop { background: #0009; }
 .booking-review h2 { font-size: 2rem; }
 .review-facts { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 190px), 1fr)); gap: .7rem; margin: 0; }
 .review-facts dt { color: var(--muted); font-size: .8rem; }
 .review-facts dd { margin: 0; overflow-wrap: anywhere; }
 .review-notes { grid-column: 1 / -1; white-space: pre-wrap; }
 .booking { max-width: 1280px; background: var(--bg); color: var(--text); }

 .booking-source { max-width: 18rem; }
 .booking-layout { display: grid; gap: 20px; align-items: start; }
 .booking-steps { min-width: 0; gap: 24px; }
 .booking-cart { border-top: 4px solid var(--accent); border-radius: 12px; padding: 20px; box-shadow: 0 4px 12px var(--card-shadow); }
 .booking-cart .btn { width: 100%; clip-path: none; border-radius: 8px; }
 @media (min-width: 960px) {
  .booking-layout { grid-template-columns: minmax(0, 2fr) minmax(280px, 1fr); gap: 24px; }
  .booking-cart { position: sticky; top: 80px; max-height: calc(100vh - 100px); overflow: auto; }
 }
 legend span { display: inline-grid; place-items: center; width: 1.65em; aspect-ratio: 1; margin-inline-end: 6px; border-radius: 50%; background: var(--accent-fill); color: var(--accent-ink); font-size: .82em; }
 h1 { font-family: var(--body); font-size: clamp(2rem, 5vw, 3.25rem); font-weight: 900; font-style: italic; letter-spacing: -.03em; }
 fieldset { min-inline-size: 0; margin: 0; }
 legend { padding-inline: 6px; font-weight: 750; font-size: 1.2rem; }
 .booking-panel {
  padding: clamp(16px, 3vw, 28px);
  gap: 18px;
  border-radius: 12px;
  box-shadow: 0 1px 3px var(--card-shadow);
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
 .model-group { grid-row: span 5; grid-template-rows: subgrid; align-items: start; }
 .tier-heading { grid-row: span 4; grid-template-rows: subgrid; align-self: stretch; }
 .tier-price { align-self: end; }
 .model-options { display: grid; gap: 2px; border-top: 1px solid var(--line); margin-top: 6px; padding-top: 6px; }
 .model { display: flex; align-items: center; gap: 8px; min-height: 38px; padding: 4px 7px; border-radius: 6px; color: var(--text); font-size: .9rem; cursor: pointer; }
 .model input { flex: none; width: 1rem; height: 1rem; margin: 0; accent-color: var(--accent); }
 .model:hover, .model:has(:checked) { background: var(--panel-2); }
 .model:has(:checked) { box-shadow: inset 0 0 0 1px var(--accent); }
 .model:has(:focus-visible) { outline: 2px solid var(--accent); outline-offset: 2px; }
 .cart-title { padding-bottom: 12px; border-bottom: 1px solid var(--line); font-family: var(--body); font-size: 1.15rem; font-weight: 900; font-style: italic; letter-spacing: -.03em; }
 .cart-line { display: flex; justify-content: space-between; gap: 10px; }
 .cart-line strong { text-align: right; }
 .price-adjustment { grid-template-columns: 1fr minmax(0, 8.5rem); align-items: center; gap: .4rem; font-size: .8rem; }
 .price-adjustment input { min-height: 38px; padding: .35rem .5rem; }
 .cart-total { border-top: 1px solid var(--line); padding-top: 10px; }
 .check { display: flex; align-items: center; gap: 8px; }
 .contact-panel > .cols { grid-template-columns: repeat(auto-fit, minmax(min(100%, 190px), 1fr)); }
 .contact-panel label { align-content: start; font-weight: 600; }
 .contact-panel input, .booking-panel textarea { background: var(--panel); border-radius: 10px; font-weight: 400; }
 .required-label { color: var(--accent); font-weight: 400; }
 .email-help { font-weight: 400; }
</style>
