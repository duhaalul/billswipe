begin;
create table public.push_devices (
  token text primary key check (length(token) between 20 and 4096),
  user_id uuid not null references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now()
);
alter table public.push_devices enable row level security;
revoke all on public.push_devices from anon, authenticated;
grant select, delete on public.push_devices to authenticated;
grant all on public.push_devices to service_role;
create policy push_device_owner_read on public.push_devices for select to authenticated using(user_id = auth.uid());
create policy push_device_owner_delete on public.push_devices for delete to authenticated using(user_id = auth.uid());
create index push_devices_user on public.push_devices(user_id);
create function public.register_push_device(device_token text) returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if length(device_token) not between 20 and 4096 then raise exception 'Invalid token'; end if;
  insert into public.push_devices(token,user_id) values(device_token,auth.uid())
  on conflict(token) do update set user_id=auth.uid(), updated_at=now();
end;
$$;
revoke all on function public.register_push_device(text) from public, anon;
grant execute on function public.register_push_device(text) to authenticated;
commit;
