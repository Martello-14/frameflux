create extension if not exists pgcrypto;

-- Roles: viewers, independent creators, and the site owner.
create table if not exists public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 email text,
 full_name text default '',
 role text not null default 'viewer' check(role in('viewer','creator','admin')),
 subscription_status text not null default 'inactive' check(subscription_status in('inactive','active')),
 subscription_until timestamptz,
 created_at timestamptz not null default now()
);

create table if not exists public.creator_pages(
 id uuid primary key default gen_random_uuid(),
 creator_id uuid not null unique references auth.users(id) on delete cascade,
 display_name text not null,
 bio text default '',
 monthly_price_kobo integer not null default 250000 check(monthly_price_kobo between 10000 and 100000000),
 published boolean not null default false,
 created_at timestamptz not null default now()
);

create table if not exists public.videos(
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 title text not null,
 description text default '',
 category text not null default 'Cinematic',
 access text not null default 'creator_subscribers' check(access in('creator_subscribers','free_preview')),
 storage_path text not null,
 poster_url text,
 published boolean not null default true,
 created_at timestamptz not null default now()
);

create table if not exists public.creator_subscriptions(
 id uuid primary key default gen_random_uuid(),
 subscriber_id uuid not null references auth.users(id) on delete cascade,
 creator_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'inactive' check(status in('inactive','active','cancelled','expired')),
 started_at timestamptz,
 expires_at timestamptz,
 payment_reference text unique,
 amount_kobo integer not null,
 created_at timestamptz not null default now(),
 unique(subscriber_id,creator_id)
);

create table if not exists public.video_reactions(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 video_id uuid not null references public.videos(id) on delete cascade,
 reaction text not null check(reaction in('like','dislike')),
 created_at timestamptz not null default now(),
 unique(user_id,video_id)
);

create table if not exists public.video_comments(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 video_id uuid not null references public.videos(id) on delete cascade,
 body text not null check(char_length(body) between 1 and 2000),
 created_at timestamptz not null default now()
);

create table if not exists public.saved_videos(
 user_id uuid not null references auth.users(id) on delete cascade,
 video_id uuid not null references public.videos(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(user_id,video_id)
);

create table if not exists public.payments(
 id uuid primary key default gen_random_uuid(),
 reference text not null unique,
 user_id uuid not null references auth.users(id),
 creator_id uuid references auth.users(id),
 amount integer not null,
 platform_commission_kobo integer,
 creator_earning_kobo integer,
 currency text not null default 'NGN',
 payment_type text not null default 'creator_subscription',
 status text not null,
 created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.creator_pages enable row level security;
alter table public.videos enable row level security;
alter table public.creator_subscriptions enable row level security;
alter table public.video_reactions enable row level security;
alter table public.video_comments enable row level security;
alter table public.saved_videos enable row level security;
alter table public.payments enable row level security;

create or replace function public.is_frameflux_admin() returns boolean
language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin'); $$;

create or replace function public.is_creator_subscriber(target_creator uuid) returns boolean
language sql stable security definer set search_path=public
as $$ select exists(
 select 1 from public.creator_subscriptions
 where subscriber_id=auth.uid() and creator_id=target_creator
 and status='active' and expires_at>now()
); $$;

create policy "read profiles" on public.profiles for select to authenticated
using(id=auth.uid() or public.is_frameflux_admin());
create policy "create viewer or creator profile" on public.profiles for insert to authenticated
with check(id=auth.uid() and role in('viewer','creator'));
create policy "update own profile safe fields" on public.profiles for update to authenticated
using(id=auth.uid()) with check(id=auth.uid() and role in('viewer','creator'));

create policy "published creator pages visible" on public.creator_pages for select to anon,authenticated
using(published=true or creator_id=auth.uid() or public.is_frameflux_admin());
create policy "creator manages own page" on public.creator_pages for all to authenticated
using(creator_id=auth.uid() or public.is_frameflux_admin())
with check((creator_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in('creator','admin'))) or public.is_frameflux_admin());

create policy "published video catalogue visible" on public.videos for select to anon,authenticated
using(published=true);
create policy "creators manage own videos" on public.videos for all to authenticated
using(owner_id=auth.uid() or public.is_frameflux_admin())
with check((owner_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in('creator','admin'))) or public.is_frameflux_admin());

create policy "subscriptions visible to parties" on public.creator_subscriptions for select to authenticated
using(subscriber_id=auth.uid() or creator_id=auth.uid() or public.is_frameflux_admin());
create policy "reactions readable" on public.video_reactions for select to anon,authenticated using(true);
create policy "users manage own reactions" on public.video_reactions for all to authenticated
using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "comments readable" on public.video_comments for select to anon,authenticated using(true);
create policy "signed in users comment" on public.video_comments for insert to authenticated with check(user_id=auth.uid());
create policy "users delete own comments" on public.video_comments for delete to authenticated using(user_id=auth.uid() or public.is_frameflux_admin());
create policy "saved videos private" on public.saved_videos for select to authenticated using(user_id=auth.uid());
create policy "users manage saved videos" on public.saved_videos for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "read own payments" on public.payments for select to authenticated using(user_id=auth.uid() or creator_id=auth.uid() or public.is_frameflux_admin());

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public
as $$ begin
 insert into public.profiles(id,email,full_name,role)
 values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name',''),case when new.raw_user_meta_data->>'account_type'='creator' then 'creator' else 'viewer' end)
 on conflict(id) do nothing;
 return new;
end; $$;
drop trigger if exists on_auth_user_created_frameflux on auth.users;
create trigger on_auth_user_created_frameflux after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Storage: create private 'videos' and public 'posters' buckets in Supabase.
create policy "creators upload their own video files" on storage.objects for insert to authenticated
with check(bucket_id='videos' and (storage.foldername(name))[1]=auth.uid()::text
 and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in('creator','admin')));
create policy "creators manage own media" on storage.objects for all to authenticated
using(bucket_id in('videos','posters') and ((storage.foldername(name))[1]=auth.uid()::text or public.is_frameflux_admin()))
with check(bucket_id in('videos','posters') and ((storage.foldername(name))[1]=auth.uid()::text or public.is_frameflux_admin()));
create policy "posters are public" on storage.objects for select to anon,authenticated using(bucket_id='posters');
create policy "published free preview files are readable" on storage.objects for select to anon,authenticated
using(bucket_id='videos' and exists(
 select 1 from public.videos v where v.storage_path=name and v.access='free_preview' and v.published=true
));
create policy "subscribers and creators can read video files" on storage.objects for select to authenticated
using(bucket_id='videos' and (
 public.is_frameflux_admin() or (storage.foldername(name))[1]=auth.uid()::text or
 exists(select 1 from public.creator_subscriptions s where s.subscriber_id=auth.uid()
 and s.creator_id::text=(storage.foldername(name))[1] and s.status='active' and s.expires_at>now())
));
