-- Run in a Supabase project with Anonymous Sign-Ins enabled.

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  owner_actor uuid not null references auth.users(id),
  source_room_id uuid references public.rooms(id),
  version integer not null default 0,
  data jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.room_members (
  room_id uuid not null references public.rooms(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  member_id uuid not null,
  primary key (room_id, actor_id),
  unique (room_id, member_id)
);

create index if not exists room_members_actor_idx on public.room_members(actor_id);
create index if not exists rooms_owner_idx on public.rooms(owner_actor);

alter table public.rooms enable row level security;
alter table public.room_members enable row level security;

revoke all on public.rooms from anon, authenticated;
revoke all on public.room_members from anon, authenticated;
grant select on public.rooms to authenticated;
grant select on public.room_members to authenticated;

create policy room_read_member on public.rooms for select to authenticated
using (exists (
  select 1 from public.room_members m
  where m.room_id = rooms.id and m.actor_id = (select auth.uid())
));

-- room_members is not exposed for direct client queries. The row information
-- needed by clients is provided only through the protected rooms.data field.
create policy member_self on public.room_members for select to authenticated
using (actor_id = (select auth.uid()));

create or replace function public.toong_code() returns text
language sql volatile set search_path = public, pg_temp as $$
  select upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
$$;

create or replace function public.create_toong_room(p_name text, p_nickname text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rid uuid := gen_random_uuid();
  mid uuid := gen_random_uuid();
  room_code text;
  payload jsonb;
  attempt integer := 0;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if length(trim(p_name)) not between 1 and 30 or
     length(trim(p_nickname)) not between 1 and 12 then
    raise exception '방 이름과 닉네임을 확인해주세요.';
  end if;
  loop
    attempt := attempt + 1;
    if attempt > 10 then raise exception '방 코드 생성에 실패했습니다.'; end if;
    room_code := public.toong_code();
    payload := jsonb_build_object('id', rid::text, 'code', room_code,
      'name', trim(p_name), 'owner_member_id', mid::text,
      'members', jsonb_build_array(jsonb_build_object('id', mid::text,
        'name', trim(p_nickname), 'actor_id', auth.uid()::text)),
      'expenses', '[]'::jsonb, 'version', 0, 'source_room_id', null);
    begin
      insert into public.rooms(id, code, owner_actor, data)
      values (rid, room_code, auth.uid(), payload);
      exit;
    exception when unique_violation then
      -- A randomly generated code collided; try another.
    end;
  end loop;
  insert into public.room_members(room_id, actor_id, member_id)
  values (rid, auth.uid(), mid);
  return payload;
end;
$$;

create or replace function public.join_toong_room(p_code text, p_nickname text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
  existing uuid;
  mid uuid := gen_random_uuid();
  payload jsonb;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if length(trim(p_nickname)) not between 1 and 12 then
    raise exception '닉네임을 확인해주세요.';
  end if;
  select * into rec from public.rooms
  where code = upper(trim(p_code)) for update;
  if not found then raise exception '방 코드를 찾을 수 없습니다.'; end if;
  select member_id into existing from public.room_members
  where room_id = rec.id and actor_id = auth.uid();
  if existing is not null then return rec.data; end if;
  payload := jsonb_set(rec.data, '{members}',
    (rec.data->'members') || jsonb_build_array(jsonb_build_object(
      'id', mid::text, 'name', trim(p_nickname), 'actor_id', auth.uid()::text)));
  payload := jsonb_set(payload, '{version}', to_jsonb(rec.version + 1));
  update public.rooms set data = payload, version = rec.version + 1 where id = rec.id;
  insert into public.room_members(room_id, actor_id, member_id)
  values (rec.id, auth.uid(), mid);
  return payload;
end;
$$;

create or replace function public.save_toong_room(
  p_room_id uuid, p_version integer, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
  expense jsonb;
  item jsonb;
  member_id jsonb;
  valid_ids jsonb;
  amount_value numeric;
  payload jsonb;
begin
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 수정할 수 있습니다.';
  end if;
  if rec.version <> p_version then
    raise exception '다른 기기에서 방이 바뀌었습니다. 새로고침 후 다시 시도해주세요.';
  end if;
  if p_data->'members' is distinct from rec.data->'members' or
     p_data->>'id' is distinct from rec.id::text or
     p_data->>'code' is distinct from rec.code or
     p_data->>'owner_member_id' is distinct from rec.data->>'owner_member_id' or
     p_data->>'source_room_id' is distinct from rec.data->>'source_room_id' or
     p_data->>'name' is distinct from rec.data->>'name' or
     jsonb_typeof(p_data->'expenses') is distinct from 'array' or
     jsonb_array_length(p_data->'expenses') > 200 then
    raise exception '변경할 수 없는 방 정보입니다.';
  end if;
  select coalesce(jsonb_agg(m->'id'), '[]'::jsonb) into valid_ids
  from jsonb_array_elements(rec.data->'members') m;
  for expense in select value from jsonb_array_elements(p_data->'expenses') loop
    if length(trim(expense->>'title')) not between 1 and 40 or
       not valid_ids @> jsonb_build_array(expense->'payer_id') or
       jsonb_typeof(expense->'items') is distinct from 'array' or
       jsonb_array_length(expense->'items') not between 1 and 100 then
      raise exception '지출을 확인해주세요.';
    end if;
    for item in select value from jsonb_array_elements(expense->'items') loop
      if length(trim(item->>'name')) not between 1 and 40 or
         jsonb_typeof(item->'member_ids') is distinct from 'array' or
         jsonb_array_length(item->'member_ids') < 1 or
         not valid_ids @> item->'member_ids' or
         jsonb_array_length(item->'member_ids') <> (
           select count(distinct value) from jsonb_array_elements(item->'member_ids')) then
        raise exception '항목의 이름과 부담자를 확인해주세요.';
      end if;
      if (item->>'amount') !~ '^[0-9]{1,9}$' then
        raise exception '항목 금액을 확인해주세요.';
      end if;
      amount_value := (item->>'amount')::numeric;
      if amount_value < 1 or amount_value > 100000000 then
        raise exception '항목 금액을 확인해주세요.';
      end if;
      member_id := item->'remainder_member_id';
      if member_id is not null and member_id <> 'null'::jsonb and
         not (item->'member_ids') @> jsonb_build_array(member_id) then
        raise exception '잔돈 부담자가 해당 항목에 없습니다.';
      end if;
    end loop;
  end loop;
  payload := jsonb_set(p_data, '{version}', to_jsonb(rec.version + 1));
  update public.rooms set data = payload, version = rec.version + 1 where id = rec.id;
  return payload;
end;
$$;

create or replace function public.clone_toong_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  source public.rooms%rowtype;
  my_member uuid;
  rid uuid := gen_random_uuid();
  room_code text;
  payload jsonb;
  copied_members jsonb;
  attempt integer := 0;
begin
  select * into source from public.rooms where id = p_room_id;
  select member_id into my_member from public.room_members
  where room_id = p_room_id and actor_id = auth.uid();
  if source.id is null or my_member is null then
    raise exception '참여 중인 방만 복제할 수 있습니다.';
  end if;
  select jsonb_agg(jsonb_set(m, '{actor_id}',
    case when m->>'id' = my_member::text then to_jsonb(auth.uid()::text)
    else 'null'::jsonb end)) into copied_members
  from jsonb_array_elements(source.data->'members') m;
  loop
    attempt := attempt + 1;
    if attempt > 10 then raise exception '방 코드 생성에 실패했습니다.'; end if;
    room_code := public.toong_code();
    payload := source.data || jsonb_build_object(
      'id', rid::text, 'code', room_code,
      'name', left((source.data->>'name') || ' 복제', 30),
      'owner_member_id', my_member::text, 'members', copied_members,
      'version', 0, 'source_room_id', source.id::text);
    begin
      insert into public.rooms(id, code, owner_actor, source_room_id, data)
      values(rid, room_code, auth.uid(), source.id, payload);
      exit;
    exception when unique_violation then
    end;
  end loop;
  insert into public.room_members(room_id, actor_id, member_id)
  values(rid, auth.uid(), my_member);
  return payload;
end;
$$;

create or replace function public.link_toong_member(
  p_room_id uuid, p_historical_id uuid, p_joined_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
  joined_actor uuid;
  old_member jsonb;
  new_member jsonb;
  expense jsonb;
  item jsonb;
  merged jsonb;
  payload jsonb;
begin
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 기록을 연결할 수 있습니다.';
  end if;
  select actor_id into joined_actor from public.room_members
  where room_id = p_room_id and member_id = p_joined_id;
  select value into old_member from jsonb_array_elements(rec.data->'members')
  where value->>'id' = p_historical_id::text;
  select value into new_member from jsonb_array_elements(rec.data->'members')
  where value->>'id' = p_joined_id::text;
  if joined_actor is null or old_member is null or new_member is null or
     old_member->'actor_id' <> 'null'::jsonb or
     p_joined_id::text = rec.data->>'owner_member_id' then
    raise exception '연결할 수 없는 참여자입니다.';
  end if;
  for expense in select value from jsonb_array_elements(rec.data->'expenses') loop
    if expense->>'payer_id' = p_joined_id::text then
      raise exception '새 참여자에게 등록된 지출이 있어 연결할 수 없습니다.';
    end if;
    for item in select value from jsonb_array_elements(expense->'items') loop
      if item->'member_ids' @> jsonb_build_array(p_joined_id::text) then
        raise exception '새 참여자에게 등록된 지출이 있어 연결할 수 없습니다.';
      end if;
    end loop;
  end loop;
  select jsonb_agg(case when m->>'id' = p_historical_id::text
    then jsonb_set(m, '{actor_id}', to_jsonb(joined_actor::text))
    else m end) into merged
  from jsonb_array_elements(rec.data->'members') m
  where m->>'id' <> p_joined_id::text;
  payload := jsonb_set(rec.data, '{members}', merged);
  payload := jsonb_set(payload, '{version}', to_jsonb(rec.version + 1));
  delete from public.room_members where room_id = p_room_id and member_id = p_joined_id;
  insert into public.room_members(room_id, actor_id, member_id)
  values(p_room_id, joined_actor, p_historical_id);
  update public.rooms set data = payload, version = rec.version + 1 where id = rec.id;
  return payload;
end;
$$;

revoke all on function public.toong_code() from public, anon, authenticated;
revoke all on function public.create_toong_room(text, text) from public, anon;
revoke all on function public.join_toong_room(text, text) from public, anon;
revoke all on function public.save_toong_room(uuid, integer, jsonb) from public, anon;
revoke all on function public.clone_toong_room(uuid) from public, anon;
revoke all on function public.link_toong_member(uuid, uuid, uuid) from public, anon;
grant execute on function public.create_toong_room(text, text) to authenticated;
grant execute on function public.join_toong_room(text, text) to authenticated;
grant execute on function public.save_toong_room(uuid, integer, jsonb) to authenticated;
grant execute on function public.clone_toong_room(uuid) to authenticated;
grant execute on function public.link_toong_member(uuid, uuid, uuid) to authenticated;
