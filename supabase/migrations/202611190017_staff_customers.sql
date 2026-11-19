begin;

create function herco_private.require_customers_page()
returns void
language plpgsql volatile set search_path = '' as $$
begin
  if auth.uid() is null or (auth.jwt()->>'aal') is distinct from 'aal2' then
    raise exception 'Verify your staff session first.' using errcode = '42501';
  end if;

  perform 1 from herco_private.staff_memberships as m
  where m.user_id = auth.uid() and m.enabled and 'Customers' = any (m.page_grants)
  for share;
  if not found then
    raise exception 'You do not have access to customers.' using errcode = '42501';
  end if;
end;
$$;

create function public.herco_staff_customers(search_term text default '', after_customer uuid default null)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  term text := lower(btrim(coalesce(search_term, '')));
  search_email boolean := position('@' in term) > 0;
  matches jsonb;
begin
  perform herco_private.require_customers_page();
  if char_length(term) > 254 or (term <> '' and char_length(term) < 2)
    or (search_email and term !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$') then
    raise exception 'Enter at least two name characters or a complete email address.' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(to_jsonb(matches_page) order by matches_page.id), '[]'::jsonb)
  into matches
  from (
    select u.id, u.email, recent.name
    from auth.users as u
    cross join lateral (
      select b.customer_contact->>'name' as name
      from public.herco_bookings as b
      where b.customer_id = u.id
      order by b.created_at desc, b.id desc
      limit 1
    ) as recent
    where u.email_confirmed_at is not null and nullif(btrim(u.email), '') is not null
      and (after_customer is null or u.id > after_customer)
      and (term = '' or (case when search_email then lower(u.email) = term
        else starts_with(lower(recent.name), term) end))
    order by u.id
    limit 21
  ) as matches_page;

  return jsonb_build_object('customers', matches - 20,
    'nextCursor', case when jsonb_array_length(matches) > 20 then matches->19->>'id' end);
end;
$$;

create function public.herco_staff_customer_visits(customer uuid, visit_page integer default 1)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  visits jsonb;
begin
  perform herco_private.require_customers_page();
  if customer is null or visit_page is null or visit_page not between 1 and 50 then
    raise exception 'Choose a customer and valid visit page.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from auth.users as u
    where u.id = customer and u.email_confirmed_at is not null and nullif(btrim(u.email), '') is not null
      and exists (select 1 from public.herco_bookings as b where b.customer_id = u.id)
  ) then
    raise exception 'Customer not found.' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object('id', matches.id, 'visit_date', matches.visit_date,
      'visit_hour', matches.visit_hour, 'status', matches.status)
    order by matches.created_at desc, matches.id desc), '[]'::jsonb)
  into visits
  from (
    select b.id, b.visit_date, b.visit_hour, b.status, b.created_at
    from public.herco_bookings as b
    where b.customer_id = customer
    order by b.created_at desc, b.id desc
    offset ((visit_page - 1) * 20) limit 21
  ) as matches;

  return jsonb_build_object('visits', visits - 20, 'hasMore', visit_page < 50 and jsonb_array_length(visits) > 20);
end;
$$;

revoke all on function herco_private.require_customers_page() from public, anon, authenticated;
revoke all on function public.herco_staff_customers(text, uuid),
  public.herco_staff_customer_visits(uuid, integer) from public, anon, authenticated;
grant execute on function public.herco_staff_customers(text, uuid),
  public.herco_staff_customer_visits(uuid, integer) to authenticated;

commit;
