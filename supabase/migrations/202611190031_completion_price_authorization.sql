begin;

create function herco_private.check_completion_price_authorization()
returns trigger language plpgsql volatile set search_path = '' as $$
declare finalized_total bigint;
begin
  -- Administrative data recovery may import the original audited record.
  if auth.uid() is null then return new; end if;
  select coalesce(b.current_total_centavos,b.original_total_centavos) into strict finalized_total
    from public.herco_bookings b where b.id=new.booking_id;
  if new.final_price_centavos is distinct from finalized_total then
    begin
      perform herco_private.require_price_adjustment();
    exception when insufficient_privilege then
      raise exception 'Changing the final charge requires price adjustment permission.' using errcode = '42501';
    end;
  end if;
  return new;
end;
$$;
revoke all on function herco_private.check_completion_price_authorization() from public,anon,authenticated;

create trigger herco_completion_price_authorization
  before insert on herco_private.booking_completion
  for each row execute function herco_private.check_completion_price_authorization();

commit;
