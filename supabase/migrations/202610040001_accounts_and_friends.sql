-- Run once in the Supabase SQL editor. No payment provider secrets belong here.
begin;
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(display_name) between 1 and 100),
  friend_code text unique not null default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
  qris_path text,
  created_at timestamptz not null default now()
);
create function public.new_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name) values
    (new.id, left(coalesce(nullif(new.raw_user_meta_data->>'full_name',''), nullif(new.raw_user_meta_data->>'name',''), 'Pengguna BillSwipe'),100));
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.new_profile();
insert into public.profiles(id, display_name)
select id, left(coalesce(nullif(raw_user_meta_data->>'full_name',''), 'Pengguna BillSwipe'),100) from auth.users
on conflict do nothing;

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester uuid not null references public.profiles(id) on delete cascade,
  recipient uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  check (requester <> recipient)
);
create unique index friendship_pair on public.friendships(least(requester,recipient), greatest(requester,recipient));
create index friendship_recipient on public.friendships(recipient);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index notifications_owner on public.notifications(user_id, created_at desc);

create table public.payment_requests (
  id uuid primary key default gen_random_uuid(),
  sender uuid not null references public.profiles(id) on delete cascade,
  recipient uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null check (amount between 1 and 100000000),
  note text not null check (length(note) between 1 and 200),
  client_ref text not null check (length(client_ref) between 1 and 100),
  status text not null default 'pending' check (status in ('pending','paid','expired','cancelled')),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique(sender,recipient,client_ref),
  check (sender <> recipient)
);
create index payment_recipient on public.payment_requests(recipient);

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.notifications enable row level security;
alter table public.payment_requests enable row level security;
revoke all on public.profiles,public.friendships,public.notifications,public.payment_requests from anon,authenticated;
grant select on public.profiles,public.friendships,public.notifications,public.payment_requests to authenticated;
grant update(display_name,qris_path) on public.profiles to authenticated;
grant update(is_read) on public.notifications to authenticated;
create policy profile_read on public.profiles for select to authenticated using (
 id = auth.uid() or exists(select 1 from public.friendships f where f.status='accepted'
 and ((f.requester=auth.uid() and f.recipient=profiles.id) or (f.recipient=auth.uid() and f.requester=profiles.id)))
);
create policy profile_edit on public.profiles for update to authenticated using(id=auth.uid())
 with check(id=auth.uid() and (qris_path is null or qris_path like auth.uid()::text || '/%'));
create policy friendship_read on public.friendships for select to authenticated using(auth.uid() in (requester,recipient));
create policy notification_read on public.notifications for select to authenticated using(user_id=auth.uid());
create policy notification_seen on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy payment_read on public.payment_requests for select to authenticated using(auth.uid() in (sender,recipient));

create function public.request_friend(code text) returns uuid language plpgsql security definer set search_path='' as $$
declare me uuid := auth.uid(); other uuid; request_id uuid; existing public.friendships;
begin
 if me is null then raise exception 'Silakan masuk.'; end if;
 select id into other from public.profiles where friend_code=upper(trim(code));
 if other is null then raise exception 'Kode teman tidak ditemukan.'; end if;
 if other=me then raise exception 'Kode tersebut milik Anda sendiri.'; end if;
 select * into existing from public.friendships where least(requester,recipient)=least(me,other) and greatest(requester,recipient)=greatest(me,other) for update;
 if found then
   if existing.status='accepted' then raise exception 'Anda sudah berteman.'; end if;
   if existing.status='pending' then raise exception 'Permintaan sudah ada. Periksa daftar permintaan.'; end if;
   raise exception 'Permintaan ini sudah ditolak.';
 end if;
 insert into public.friendships(requester,recipient) values(me,other) returning id into request_id;
 insert into public.notifications(user_id,title,body) values(other,'Permintaan teman', (select display_name from public.profiles where id=me) || ' ingin berteman dengan Anda.');
 return request_id;
end; $$;

create function public.respond_friend(request_id uuid, accept_request boolean) returns void language plpgsql security definer set search_path='' as $$
declare f public.friendships;
begin
 select * into f from public.friendships where id=request_id for update;
 if f.id is null or f.recipient<>auth.uid() or auth.uid() is null or f.status<>'pending' then raise exception 'Permintaan tidak dapat diubah.'; end if;
 update public.friendships set status=case when accept_request then 'accepted' else 'declined' end where id=request_id;
 insert into public.notifications(user_id,title,body) values(f.requester,'Permintaan teman',
   (select display_name from public.profiles where id=auth.uid()) || case when accept_request then ' menerima permintaan Anda.' else ' menolak permintaan Anda.' end);
end; $$;

create function public.social_connections() returns table(request_id uuid, user_id uuid, display_name text, status text, incoming boolean)
language sql security definer set search_path='' as $$
 select f.id,p.id,p.display_name,f.status,f.recipient=auth.uid()
 from public.friendships f join public.profiles p on p.id=case when f.requester=auth.uid() then f.recipient else f.requester end
 where auth.uid() in (f.requester,f.recipient) and f.status in ('pending','accepted') order by f.created_at desc;
$$;

create function public.request_payment(friend_id uuid, amount_rupiah bigint, description text, reference text) returns uuid
language plpgsql security definer set search_path='' as $$
declare me uuid:=auth.uid(); result uuid; prior public.payment_requests;
begin
 if me is null or not exists(select 1 from public.friendships where status='accepted' and
 ((requester=me and recipient=friend_id) or (requester=friend_id and recipient=me))) then raise exception 'Penerima harus sudah menjadi teman.'; end if;
 if amount_rupiah is null or amount_rupiah<1 or amount_rupiah>100000000 then raise exception 'Nominal tidak valid.'; end if;
 if not exists(select 1 from public.profiles where id=me and qris_path is not null) then raise exception 'Unggah QRIS pada akun Anda terlebih dahulu.'; end if;
 insert into public.payment_requests(sender,recipient,amount,note,client_ref)
 values(me,friend_id,amount_rupiah,trim(description),reference) on conflict(sender,recipient,client_ref) do nothing returning id into result;
 if result is null then
   select * into prior from public.payment_requests where sender=me and recipient=friend_id and client_ref=reference;
   if prior.amount<>amount_rupiah then raise exception 'Tagihan sudah dikirim dengan nominal berbeda. Buat tagihan baru.'; end if;
   return prior.id;
 end if;
 insert into public.notifications(user_id,title,body) values(friend_id,'Tagihan baru',
 (select display_name from public.profiles where id=me) || ' mengirim tagihan Rp' || amount_rupiah::text || '.');
 return result;
end; $$;

revoke all on function public.new_profile(),public.request_friend(text),public.respond_friend(uuid,boolean),public.social_connections(),public.request_payment(uuid,bigint,text,text) from public;
grant execute on function public.request_friend(text),public.respond_friend(uuid,boolean),public.social_connections(),public.request_payment(uuid,bigint,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('qris','qris',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy qris_upload on storage.objects for insert to authenticated with check(bucket_id='qris' and (storage.foldername(name))[1]=auth.uid()::text);
create policy qris_update on storage.objects for update to authenticated using(bucket_id='qris' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='qris' and (storage.foldername(name))[1]=auth.uid()::text);
create policy qris_read on storage.objects for select to authenticated using(bucket_id='qris' and (
 (storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.friendships f where f.status='accepted' and
 ((f.requester=auth.uid() and f.recipient::text=(storage.foldername(name))[1]) or (f.recipient=auth.uid() and f.requester::text=(storage.foldername(name))[1])))));

alter publication supabase_realtime add table public.friendships,public.notifications,public.payment_requests;
-- Clients cannot mark requests paid. Only a future verified server webhook may do that.
commit;
