-- F-017 maintenance reminder. Run against a fresh local or CI database after every migration. Fictional data only.
begin;

-- Test helpers (rolled back with the rest).
-- herco_test_done: a booking that staff mark Done (same two writes as herco_complete_booking), event time chosen by the test.
create function public.herco_test_done(p_customer uuid, p_email text, p_name text, p_created timestamptz) returns uuid language plpgsql as $$
declare b uuid := gen_random_uuid();
begin
  insert into public.herco_bookings (id,customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,
    original_services,original_total_centavos,status)
  values (b,p_customer,gen_random_uuid(),'{}',current_date - 200,10,'Fixture bike',
    jsonb_build_object('name',p_name,'email',p_email),
    '[{"code":"ceramic","label":"Ceramic coating","price_centavos":1000}]',1000,'confirmed');
  update public.herco_bookings set status = 'done' where id = b;
  insert into public.herco_booking_events (booking_id,actor_id,kind,to_status,created_at)
  values (b,'00000000-0000-4000-8000-000000000503','completed','done',p_created);
  return b;
end $$;
-- herco_test_job: the reminder job of a booking, claimed (leased) as the Worker would.
create function public.herco_test_job(b uuid) returns table (id bigint, token uuid) language plpgsql as $$
declare t uuid := gen_random_uuid();
begin
  return query
    update herco_private.notification_outbox o
    set lease_token = t, lease_until = now() + interval '2 minutes', attempts = 1
    where o.template = 'maintenance_reminder' and o.payload->>'booking_id' = b::text
    returning o.id, t;
end $$;
-- herco_test_upcoming: an upcoming booking for a customer in the given status.
create function public.herco_test_upcoming(p_customer uuid, p_status text, p_days integer) returns void language plpgsql as $$
begin
  insert into public.herco_bookings (customer_id,request_id,request_payload,visit_date,visit_hour,bike,customer_contact,
    original_services,original_total_centavos,status)
  values (p_customer,gen_random_uuid(),'{}',current_date + p_days,10,'Fixture bike','{}','[]',0,p_status);
end $$;

insert into auth.users(id,email,email_confirmed_at) values
  ('00000000-0000-4000-8000-000000000501','reminder-a@example.test',now()),
  ('00000000-0000-4000-8000-000000000502','reminder-b@example.test',now()),
  ('00000000-0000-4000-8000-000000000503','reminder-staff@example.test',now());

-- 1. Marking Done queues one job at 9 AM Philippine time, 6 months later, month-end clamped.
do $$
declare
  a uuid := '00000000-0000-4000-8000-000000000501';
  b uuid;
  j herco_private.notification_outbox;
  created text[] := array['2026-08-31 10:00+08','2026-01-10 10:00+08','2026-01-10 23:30+08','2026-01-10 16:30+00',
    '2027-08-31 12:00+08','2026-12-31 12:00+08','2026-07-31 12:00+08'];
  due text[] := array['2027-02-28 09:00+08','2026-07-10 09:00+08','2026-07-10 09:00+08','2026-07-11 09:00+08',
    '2028-02-29 09:00+08','2027-06-30 09:00+08','2027-01-31 09:00+08'];
  i integer;
begin
  for i in 1 .. array_length(created, 1) loop
    b := public.herco_test_done(a, 'ana@example.test', 'Ana Reyes', created[i]::timestamptz);
    select o.* into j from herco_private.notification_outbox o
      where o.template = 'maintenance_reminder' and o.payload->>'booking_id' = b::text;
    if not found then raise exception 'No reminder queued for case %', i; end if;
    if j.available_at <> due[i]::timestamptz then
      raise exception 'Case %: expected % but queued %', i, due[i], j.available_at; end if;
    if j.recipient <> 'ana@example.test' then raise exception 'Wrong recipient'; end if;
    if j.payload <> jsonb_build_object('booking_id', b, 'customer_id', a) then
      raise exception 'Payload holds more than the booking and customer ids'; end if;
    if j.sent_at is not null or j.skipped_at is not null then raise exception 'New job is not pending'; end if;
  end loop;
end $$;

-- A booking with no email address queues nothing and does not fail the Done save.
do $$
declare b uuid := public.herco_test_done('00000000-0000-4000-8000-000000000501', '  ', 'No Email', now());
begin
  if exists (select 1 from herco_private.notification_outbox where payload->>'booking_id' = b::text) then
    raise exception 'A reminder was queued without an email address'; end if;
end $$;

-- 2. One per booking: Done, undo, Done again keeps one job; undo cancels it; Done again revives it.
do $$
declare
  a uuid := '00000000-0000-4000-8000-000000000501';
  b uuid := public.herco_test_done(a, 'ana@example.test', 'Ana', '2026-03-01 10:00+08');
  j herco_private.notification_outbox;
begin
  update public.herco_bookings set status = 'confirmed' where id = b;
  select o.* into j from herco_private.notification_outbox o where o.template = 'maintenance_reminder' and o.payload->>'booking_id' = b::text;
  if j.skipped_at is null or j.last_outcome <> 'stale' then raise exception 'Leaving Done did not cancel the reminder'; end if;

  update public.herco_bookings set status = 'done' where id = b;
  insert into public.herco_booking_events (booking_id,actor_id,kind,to_status,created_at)
    values (b,'00000000-0000-4000-8000-000000000503','completed','done','2026-03-05 10:00+08');
  if (select count(*) from herco_private.notification_outbox o where o.template = 'maintenance_reminder' and o.payload->>'booking_id' = b::text) <> 1 then
    raise exception 'Done twice made two reminders'; end if;
  select o.* into j from herco_private.notification_outbox o where o.template = 'maintenance_reminder' and o.payload->>'booking_id' = b::text;
  if j.skipped_at is not null or j.available_at <> '2026-09-05 09:00+08'::timestamptz then
    raise exception 'Done again did not revive the reminder for the new date'; end if;

  -- A job that was already sent is never re-queued.
  update herco_private.notification_outbox set sent_at = now() where id = j.id;
  update public.herco_bookings set status = 'confirmed' where id = b;
  update public.herco_bookings set status = 'done' where id = b;
  insert into public.herco_booking_events (booking_id,actor_id,kind,to_status) values (b,'00000000-0000-4000-8000-000000000503','completed','done');
  if (select count(*) from herco_private.notification_outbox o where o.template = 'maintenance_reminder' and o.payload->>'booking_id' = b::text) <> 1
    or (select o.skipped_at from herco_private.notification_outbox o where o.id = j.id) is not null
    or (select o.sent_at from herco_private.notification_outbox o where o.id = j.id) is null then
    raise exception 'A sent reminder was changed or duplicated'; end if;
end $$;

-- Other events on a Done booking (price correction, service edit, change request) leave the job alone.
do $$
declare
  a uuid := '00000000-0000-4000-8000-000000000501';
  b uuid := public.herco_test_done(a, 'ana@example.test', 'Ana', '2026-03-01 10:00+08');
  due timestamptz;
  k text;
begin
  select o.available_at into due from herco_private.notification_outbox o where o.template = 'maintenance_reminder' and o.payload->>'booking_id' = b::text;
  foreach k in array array['price_corrected', 'services_edited', 'details_shared', 'change_requested'] loop
    insert into public.herco_booking_events (booking_id,actor_id,kind,to_status,created_at)
      values (b,'00000000-0000-4000-8000-000000000503',k,'done','2026-05-20 10:00+08');
  end loop;
  if (select o.available_at from herco_private.notification_outbox o where o.template = 'maintenance_reminder' and o.payload->>'booking_id' = b::text) <> due then
    raise exception 'A non-Done event moved the reminder date'; end if;

  -- a skipped job (booking left Done) stays skipped when such an event is written
  update public.herco_bookings set status = 'confirmed' where id = b;
  insert into public.herco_booking_events (booking_id,actor_id,kind,to_status)
    values (b,'00000000-0000-4000-8000-000000000503','price_corrected','done');
  if (select o.skipped_at from herco_private.notification_outbox o where o.template = 'maintenance_reminder' and o.payload->>'booking_id' = b::text) is null then
    raise exception 'A non-Done event revived a skipped reminder'; end if;
end $$;

-- A second job for the same booking is refused by the database.
do $$
declare b uuid := public.herco_test_done('00000000-0000-4000-8000-000000000501', 'ana@example.test', 'Ana', now());
  e bigint;
begin
  -- a different event, so only the one-per-booking rule can refuse the second job
  insert into public.herco_booking_events (booking_id,actor_id,kind,to_status)
    values (b,'00000000-0000-4000-8000-000000000503','booking_confirmed','confirmed') returning id into e;
  begin
    insert into herco_private.notification_outbox(event_id,template,recipient,payload)
    values (e, 'maintenance_reminder', 'x@example.test', jsonb_build_object('booking_id', b));
    raise exception 'Second reminder for one booking was accepted';
  exception when unique_violation then null;
  end;
end $$;

-- 3. Send-time re-check (the Worker calls this with its claim). Default hours are 9-17, Wednesday-Sunday.
do $$
declare
  a uuid := '00000000-0000-4000-8000-000000000501';
  other uuid := '00000000-0000-4000-8000-000000000502';
  b uuid; job record; answer jsonb;
begin
  -- ready: only first name, service names and default hours come back
  b := public.herco_test_done(a, 'ana@example.test', 'Ana Reyes', '2026-03-01 10:00+08');
  select * into job from public.herco_test_job(b);
  answer := public.herco_check_maintenance_reminder_outbox(job.id, job.token);
  if answer is distinct from jsonb_build_object('status','ready','firstName','Ana','services',jsonb_build_array('Ceramic coating'),
    'openHour',9,'closeHour',17,'openWeekdays',jsonb_build_array(0,3,4,5,6)) then
    raise exception 'Ready answer is wrong: %', answer; end if;

  -- admin changed the default hours since the job was queued: the email follows the new hours
  update herco_private.schedule_settings set open_hour = 8, close_hour = 20, open_weekdays = '{1,2}';
  select * into job from public.herco_test_job(b);
  answer := public.herco_check_maintenance_reminder_outbox(job.id, job.token);
  if (answer->>'openHour')::int <> 8 or (answer->>'closeHour')::int <> 20 or answer->'openWeekdays' <> '[1, 2]'::jsonb then
    raise exception 'New hours not used: %', answer; end if;
  update herco_private.schedule_settings set open_hour = 9, close_hour = 17, open_weekdays = '{0,3,4,5,6}';

  -- a wrong or reused claim returns null and changes nothing
  if public.herco_check_maintenance_reminder_outbox(job.id, gen_random_uuid()) is not null then raise exception 'Wrong token accepted'; end if;
  if public.herco_check_maintenance_reminder_outbox(-1, job.token) is not null then raise exception 'Unknown job accepted'; end if;

  -- a Pending or Confirmed upcoming booking skips it; a cancelled, done or past one does not
  perform public.herco_test_upcoming(a, 'cancelled', 5);
  perform public.herco_test_upcoming(a, 'done', 5);
  perform public.herco_test_upcoming(a, 'pending', -3);
  perform public.herco_test_upcoming(other, 'pending', 5);   -- another customer's booking does not count
  select * into job from public.herco_test_job(b);
  if public.herco_check_maintenance_reminder_outbox(job.id, job.token)->>'status' <> 'ready' then
    raise exception 'A cancelled, done, past or other customer booking skipped the reminder'; end if;
  perform public.herco_test_upcoming(a, 'pending', 5);
  select * into job from public.herco_test_job(b);
  if public.herco_check_maintenance_reminder_outbox(job.id, job.token)->>'status' <> 'stale' then
    raise exception 'A pending upcoming booking did not skip the reminder'; end if;
  if (select skipped_at from herco_private.notification_outbox where id = job.id) is null then raise exception 'Skipped job not marked'; end if;

  delete from public.herco_bookings where customer_id = a and status = 'pending' and visit_date > current_date;
  b := public.herco_test_done(a, 'ana@example.test', 'Ana', '2026-03-02 10:00+08');
  perform public.herco_test_upcoming(a, 'confirmed', 2);
  select * into job from public.herco_test_job(b);
  if public.herco_check_maintenance_reminder_outbox(job.id, job.token)->>'status' <> 'stale' then
    raise exception 'A confirmed upcoming booking did not skip the reminder'; end if;
  delete from public.herco_bookings where customer_id = a and status = 'confirmed' and visit_date > current_date;

  -- the same address in a different case or with spaces is not a change
  b := public.herco_test_done(a, 'Ana@Example.test', 'Ana', '2026-03-03 11:00+08');
  update public.herco_bookings set customer_contact = customer_contact || '{"email":"  ana@EXAMPLE.test "}' where id = b;
  select * into job from public.herco_test_job(b);
  if public.herco_check_maintenance_reminder_outbox(job.id, job.token)->>'status' <> 'ready' then
    raise exception 'A case or spacing difference in the email skipped the reminder'; end if;

  -- email changed since the job was queued
  b :=public.herco_test_done(a, 'ana@example.test', 'Ana', '2026-03-03 10:00+08');
  update public.herco_bookings set customer_contact = customer_contact || '{"email":"new@example.test"}' where id = b;
  select * into job from public.herco_test_job(b);
  if public.herco_check_maintenance_reminder_outbox(job.id, job.token)->>'status' <> 'stale' then
    raise exception 'A changed email did not skip the reminder'; end if;

  -- payload names a different customer than the booking
  b := public.herco_test_done(a, 'ana@example.test', 'Ana', '2026-03-04 10:00+08');
  update herco_private.notification_outbox set payload = jsonb_set(payload, '{customer_id}', to_jsonb(other::text))
    where payload->>'booking_id' = b::text;
  select * into job from public.herco_test_job(b);
  if public.herco_check_maintenance_reminder_outbox(job.id, job.token)->>'status' <> 'stale' then
    raise exception 'A mismatched customer did not skip the reminder'; end if;

  -- booking no longer Done even if the cancel trigger was bypassed
  b := public.herco_test_done(a, 'ana@example.test', 'Ana', '2026-03-05 10:00+08');
  alter table public.herco_bookings disable trigger herco_maintenance_reminder_cancel;
  update public.herco_bookings set status = 'confirmed' where id = b;
  alter table public.herco_bookings enable trigger herco_maintenance_reminder_cancel;
  select * into job from public.herco_test_job(b);
  if public.herco_check_maintenance_reminder_outbox(job.id, job.token)->>'status' <> 'stale' then
    raise exception 'A booking that is not Done still got a reminder'; end if;

  -- opted out: skipped for every job of that customer, other customers unaffected
  b := public.herco_test_done(a, 'ana@example.test', 'Ana', '2026-03-06 10:00+08');
  insert into herco_private.reminder_opt_outs(customer_id) values (a);
  select * into job from public.herco_test_job(b);
  if public.herco_check_maintenance_reminder_outbox(job.id, job.token)->>'status' <> 'stale' then
    raise exception 'An opted-out customer got a reminder'; end if;
  delete from public.herco_bookings where customer_id = other and visit_date > current_date;
  b := public.herco_test_done(other, 'bo@example.test', 'Bo', '2026-03-06 10:00+08');
  select * into job from public.herco_test_job(b);
  if public.herco_check_maintenance_reminder_outbox(job.id, job.token)->>'status' <> 'ready' then
    raise exception 'Another customer opt-out stopped this reminder'; end if;
  delete from herco_private.reminder_opt_outs where customer_id = a;

  -- first name only, and services follow the current (edited) services
  b := public.herco_test_done(a, 'ana@example.test', '  Maria Clara Santos ', '2026-03-07 10:00+08');
  update public.herco_bookings set current_services = '[{"code":"a","label":"Wash","price_centavos":1},{"code":"b","label":"Powder coating","price_centavos":2}]', current_total_centavos = 3 where id = b;
  select * into job from public.herco_test_job(b);
  answer := public.herco_check_maintenance_reminder_outbox(job.id, job.token);
  if answer->>'firstName' <> 'Maria' or answer->'services' <> '["Wash", "Powder coating"]'::jsonb then
    raise exception 'Name or services wrong: %', answer; end if;
  if answer::text ~* '(centavo|price|note|@|Santos)' then raise exception 'Answer holds more than it should: %', answer; end if;
end $$;

-- 4. Claiming: a Worker without the token secret (or an older Worker) never takes maintenance jobs.
do $$
declare plain integer; maint integer;
begin
  update herco_private.notification_outbox set available_at = now() - interval '1 minute',
    lease_token = null, lease_until = null, attempts = 0, skipped_at = null, sent_at = null, review_at = null, failed_at = null
    where template = 'maintenance_reminder';
  select count(*) into plain from public.herco_claim_notification_outbox(5);
  select count(*) into plain from public.herco_claim_notification_outbox(5, false, false);
  if plain <> 0 then raise exception 'Maintenance jobs were claimed without include_maintenance'; end if;
  select count(*) into maint from public.herco_claim_notification_outbox(5, false, true);
  if maint <> 5 then raise exception 'Expected 5 maintenance jobs, got %', maint; end if;
  if exists (select 1 from herco_private.notification_outbox where template = 'maintenance_reminder' and attempts > 1) then
    raise exception 'A job was claimed twice'; end if;
  -- booking emails keep flowing regardless
  insert into herco_private.notification_outbox(event_id,template,recipient,payload)
  select max(id), 'booking_submitted', 'x@example.test', '{}' from public.herco_booking_events;
  select count(*) into plain from public.herco_claim_notification_outbox(5);
  if plain <> 1 then raise exception 'A booking email was held back (got %)', plain; end if;
end $$;

-- 5. Opt-out for the signed-in customer: own setting only.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000502',true);
select set_config('test.aal','aal1',true);
do $$
begin
  if public.herco_get_maintenance_reminders() is not true then raise exception 'Default should be on'; end if;
  if public.herco_set_maintenance_reminders(false) is not false then raise exception 'Switch off failed'; end if;
  if public.herco_set_maintenance_reminders(false) is not false then raise exception 'Switching off twice failed'; end if;
  if public.herco_get_maintenance_reminders() is not false then raise exception 'Off not saved'; end if;
  begin perform public.herco_set_maintenance_reminders(null); raise exception 'Null accepted';
  exception when sqlstate '22023' then null; end;
  begin perform 1 from herco_private.reminder_opt_outs; raise exception 'Customer read the opt-out table';
  exception when insufficient_privilege then null; end;
  begin perform public.herco_unsubscribe_maintenance_reminders('00000000-0000-4000-8000-000000000501'); raise exception 'Browser role used the unsubscribe function';
  exception when insufficient_privilege then null; end;
  begin perform public.herco_check_maintenance_reminder_outbox(1, gen_random_uuid()); raise exception 'Browser role used the Worker check';
  exception when insufficient_privilege then null; end;
  begin perform public.herco_claim_notification_outbox(1, false, true); raise exception 'Browser role claimed outbox jobs';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('test.uid','00000000-0000-4000-8000-000000000501',true);
do $$
begin
  -- customer B's switch does not change customer A
  if public.herco_get_maintenance_reminders() is not true then raise exception 'Another customer''s switch changed mine'; end if;
  if public.herco_set_maintenance_reminders(true) is not true then raise exception 'Switch on failed'; end if;
end $$;

select set_config('test.uid','00000000-0000-4000-8000-000000000502',true);
do $$
begin
  if public.herco_set_maintenance_reminders(true) is not true or public.herco_get_maintenance_reminders() is not true then
    raise exception 'Turning reminders back on failed'; end if;
end $$;

-- Not signed in: refused.
select set_config('test.uid','',true);
do $$
begin
  begin perform public.herco_get_maintenance_reminders(); raise exception 'Anonymous read accepted';
  exception when insufficient_privilege then null; end;
  begin perform public.herco_set_maintenance_reminders(false); raise exception 'Anonymous write accepted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$
begin
  if exists (select 1 from herco_private.reminder_opt_outs) then raise exception 'Unexpected opt-out rows'; end if;
end $$;

-- 6. Unsubscribe link (service role only): idempotent, unknown customer harmless, booking emails untouched.
set local role anon;
do $$
begin
  begin perform public.herco_get_maintenance_reminders(); raise exception 'anon can call the account switch';
  exception when insufficient_privilege then null; end;
  begin perform public.herco_unsubscribe_maintenance_reminders('00000000-0000-4000-8000-000000000501'); raise exception 'anon can unsubscribe';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role service_role;
do $$
declare a uuid := '00000000-0000-4000-8000-000000000501';
begin
  perform public.herco_unsubscribe_maintenance_reminders(a);
  perform public.herco_unsubscribe_maintenance_reminders(a);
  perform public.herco_unsubscribe_maintenance_reminders('00000000-0000-4000-8000-0000000009ff');
  begin perform public.herco_unsubscribe_maintenance_reminders(null); raise exception 'Null accepted';
  exception when sqlstate '22023' then null; end;
end $$;
reset role;
do $$
begin
  if (select count(*) from herco_private.reminder_opt_outs) <> 1
    or not exists (select 1 from herco_private.reminder_opt_outs where customer_id = '00000000-0000-4000-8000-000000000501') then
    raise exception 'Unsubscribe should leave exactly customer A opted out'; end if;
  if (select count(*) from herco_private.notification_outbox where template = 'booking_submitted') <> 1 then
    raise exception 'Unsubscribing touched booking emails'; end if;
end $$;

-- The signed-in switch turns it back on after an unsubscribe link.
set local role authenticated;
select set_config('test.uid','00000000-0000-4000-8000-000000000501',true);
do $$
begin
  if public.herco_get_maintenance_reminders() is not false then raise exception 'Unsubscribe not visible in the switch'; end if;
  perform public.herco_set_maintenance_reminders(true);
  if public.herco_get_maintenance_reminders() is not true then raise exception 'Switch could not turn reminders back on'; end if;
end $$;
reset role;

-- 7. Privileges and table protection.
do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'herco_private.reminder_opt_outs'::regclass) then
    raise exception 'RLS is off on reminder_opt_outs'; end if;
  if has_table_privilege('anon','herco_private.reminder_opt_outs','select')
    or has_table_privilege('authenticated','herco_private.reminder_opt_outs','select,insert,update,delete') then
    raise exception 'Browser roles can reach reminder_opt_outs'; end if;
  if has_function_privilege('anon','public.herco_get_maintenance_reminders()','execute')
    or has_function_privilege('anon','public.herco_set_maintenance_reminders(boolean)','execute')
    or has_function_privilege('authenticated','public.herco_unsubscribe_maintenance_reminders(uuid)','execute')
    or has_function_privilege('authenticated','public.herco_check_maintenance_reminder_outbox(bigint,uuid)','execute')
    or has_function_privilege('authenticated','public.herco_claim_notification_outbox(integer,boolean,boolean)','execute')
    or has_function_privilege('authenticated','herco_private.enqueue_maintenance_reminder()','execute') then
    raise exception 'A reminder function is open to a browser role'; end if;
  if not has_function_privilege('service_role','public.herco_unsubscribe_maintenance_reminders(uuid)','execute')
    or not has_function_privilege('service_role','public.herco_check_maintenance_reminder_outbox(bigint,uuid)','execute')
    or not has_function_privilege('service_role','public.herco_claim_notification_outbox(integer,boolean,boolean)','execute')
    or not has_function_privilege('authenticated','public.herco_get_maintenance_reminders()','execute')
    or not has_function_privilege('authenticated','public.herco_set_maintenance_reminders(boolean)','execute') then
    raise exception 'A reminder function lacks its intended grant'; end if;
  -- the old two-argument claim call still resolves to exactly one function
  if (select count(*) from pg_proc where proname = 'herco_claim_notification_outbox' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'Claim function overloads remain'; end if;
end $$;

rollback;
