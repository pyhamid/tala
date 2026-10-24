-- Bagages Tala Ouglid : à exécuter une fois dans Supabase > SQL Editor.
-- Les visiteurs peuvent seulement ENVOYER une commande / un message et SUIVRE un colis.
-- Seul le propriétaire (connecté dans admin.html) peut lire et modifier les données.

create table if not exists public.orders (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  sens text not null,
  mode text not null,
  poids numeric,
  prix_estime text,
  nom text not null,
  tel text not null,
  adresse text,
  dest_nom text,
  dest_tel text,
  note text,
  statut text not null default 'Nouvelle'
);

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  nom text not null,
  tel text not null,
  message text not null,
  lu boolean not null default false
);

create table if not exists public.parcels (
  ref text primary key,
  tel_exp text,
  tel_dest text,
  statut text not null default 'Reçu',
  pays text,
  region text,
  livraison date,
  poids numeric,
  commentaire text,
  updated_at timestamptz not null default now()
);

alter table public.orders enable row level security;
alter table public.messages enable row level security;
alter table public.parcels enable row level security;

revoke all on public.orders, public.messages, public.parcels from anon;

drop policy if exists admin_orders on public.orders;
drop policy if exists admin_messages on public.messages;
drop policy if exists admin_parcels on public.parcels;
create policy admin_orders on public.orders for all to authenticated using (true) with check (true);
create policy admin_messages on public.messages for all to authenticated using (true) with check (true);
create policy admin_parcels on public.parcels for all to authenticated using (true) with check (true);
grant select, insert, update, delete on public.orders, public.messages, public.parcels to authenticated;

-- Numéro normalisé : sans espaces, sans indicatif (33 / 213), sans 0 initial
create or replace function public.norm_tel(t text) returns text
language sql immutable as $$
  select regexp_replace(regexp_replace(regexp_replace(coalesce(t,''), '[^0-9+]', '', 'g'), '^\+?(33|213)', ''), '^0+', '')
$$;

create or replace function public.submit_order(
  p_sens text, p_mode text, p_poids numeric, p_prix text,
  p_nom text, p_tel text, p_adresse text, p_dest_nom text, p_dest_tel text, p_note text
) returns text
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if length(trim(coalesce(p_nom,''))) < 2 or length(trim(coalesce(p_tel,''))) < 6 then
    raise exception 'nom et téléphone requis';
  end if;
  if p_sens not in ('France → Algérie','Algérie → France') then raise exception 'sens invalide'; end if;
  insert into orders(sens, mode, poids, prix_estime, nom, tel, adresse, dest_nom, dest_tel, note)
  values (p_sens, left(p_mode,60), p_poids, left(p_prix,40), left(trim(p_nom),120), left(trim(p_tel),40),
          left(p_adresse,300), left(p_dest_nom,120), left(p_dest_tel,40), left(p_note,1000))
  returning id into v_id;
  return 'CMD-' || lpad(v_id::text, 5, '0');
end $$;

create or replace function public.send_message(p_nom text, p_tel text, p_message text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if length(trim(coalesce(p_nom,''))) < 2 or length(trim(coalesce(p_message,''))) < 2 then
    raise exception 'nom et message requis';
  end if;
  insert into messages(nom, tel, message) values (left(trim(p_nom),120), left(trim(coalesce(p_tel,'')),40), left(p_message,2000));
end $$;

-- Suivi : par référence de colis, référence de commande, ou téléphone (expéditeur / destinataire)
create or replace function public.track_parcel(p_q text)
returns table(ref text, statut text, pays text, region text, livraison date, poids numeric, commentaire text)
language sql security definer set search_path = public as $$
  select p.ref, p.statut, p.pays, p.region, p.livraison, p.poids, p.commentaire
  from parcels p
  where length(trim(coalesce(p_q,''))) >= 5
    and (upper(p.ref) = upper(trim(p_q))
         or (length(norm_tel(p_q)) >= 8 and norm_tel(p_q) in (norm_tel(p.tel_exp), norm_tel(p.tel_dest))))
  union all
  select 'CMD-' || lpad(o.id::text, 5, '0'), o.statut, null, null, null, o.poids, null
  from orders o
  where upper(trim(p_q)) = 'CMD-' || lpad(o.id::text, 5, '0')
  limit 5
$$;

grant execute on function public.submit_order(text,text,numeric,text,text,text,text,text,text,text) to anon, authenticated;
grant execute on function public.send_message(text,text,text) to anon, authenticated;
grant execute on function public.track_parcel(text) to anon, authenticated;
