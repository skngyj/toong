-- 6.8 방 연장·얼리기·정산 완료와 익명 사용자 정리.
-- Run after 202611080001_room_expiry.sql. Requires the pg_cron extension.
--
-- 서버에 새로 저장하는 것은 방마다 삭제 시각(expires_at) 하나와, 방 data 안의
-- extend_count·frozen_at·completed_at 세 값뿐이다. 완료된 정산 기록은 서버에
-- 저장하지 않고 각 참여자 기기에만 남긴다.
--
-- 방이 삭제되는 시각:
--   정산 완료한 방  : 완료 12시간 뒤
--   얼린 방        : 얼린 지 7일 뒤 (녹이면 그때부터 48시간)
--   그 외          : 마지막 입력 48시간 뒤
-- 얼린 방과 완료된 방은 입장·지출 저장·기록 연결을 막는다. 복제는 허용한다.

alter table public.rooms add column if not exists expires_at timestamptz;

update public.rooms
set data = data || jsonb_build_object(
  'extend_count', 0, 'frozen_at', null, 'completed_at', null)
where not data ? 'extend_count';

-- expires_at은 방 상태에서 계산한다. 함수들은 data와 last_activity_at만 바꾸면 된다.
create or replace function public.toong_set_expiry() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  new.expires_at := coalesce(
    (new.data->>'completed_at')::timestamptz + interval '12 hours',
    (new.data->>'frozen_at')::timestamptz + interval '7 days',
    new.last_activity_at + interval '48 hours');
  return new;
end;
$$;

drop trigger if exists rooms_set_expiry on public.rooms;
create trigger rooms_set_expiry before insert or update on public.rooms
for each row execute function public.toong_set_expiry();

-- 기존 방의 expires_at을 채운다(트리거가 계산한다).
update public.rooms set last_activity_at = last_activity_at where expires_at is null;
alter table public.rooms alter column expires_at set not null;

create index if not exists rooms_expires_idx on public.rooms(expires_at);
drop index if exists public.rooms_last_activity_idx;

drop policy if exists room_read_member on public.rooms;
create policy room_read_member on public.rooms for select to authenticated
using (
  expires_at > now() and
  exists (
    select 1 from public.room_members m
    where m.room_id = rooms.id and m.actor_id = (select auth.uid())
  )
);

-- 삭제 시각이 지난 방을 막는다. p_editing이면 얼린 방·완료된 방도 막는다.
create or replace function public.toong_guard(rec public.rooms, p_editing boolean)
returns void language plpgsql set search_path = public, pg_temp as $$
begin
  if rec.expires_at <= now() then
    raise exception '48시간 동안 입력이 없어 삭제된 방입니다.';
  end if;
  if p_editing and rec.data->>'completed_at' is not null then
    raise exception '정산이 완료된 방입니다. 고치려면 정산을 복제해주세요.';
  end if;
  if p_editing and rec.data->>'frozen_at' is not null then
    raise exception '얼린 방입니다. 방장이 녹인 뒤에 입력할 수 있어요.';
  end if;
end;
$$;

-- 방이 없는 익명 사용자는 정리된다. 정리된 사용자의 토큰이 아직 살아 있을 때
-- 방을 만들거나 입장하면 TG401로 거절하고, 앱은 새 익명 사용자로 다시 시도한다.
create or replace function public.toong_require_user()
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if not exists (select 1 from auth.users where id = auth.uid()) then
    raise exception using errcode = 'TG401',
      message = '세션이 만료되었습니다. 다시 시도해주세요.';
  end if;
end;
$$;

create or replace function public.create_toong_room(p_name text, p_nickname text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rid uuid := gen_random_uuid();
  mid uuid := gen_random_uuid();
  stamp timestamptz := now();
  room_code text;
  payload jsonb;
  attempt integer := 0;
begin
  perform public.toong_require_user();
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
      'expenses', '[]'::jsonb, 'version', 0, 'source_room_id', null,
      'last_activity_at', stamp,
      'extend_count', 0, 'frozen_at', null, 'completed_at', null);
    begin
      insert into public.rooms(id, code, owner_actor, data, last_activity_at)
      values (rid, room_code, auth.uid(), payload, stamp);
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
  stamp timestamptz := now();
  payload jsonb;
begin
  perform public.toong_require_user();
  if length(trim(p_nickname)) not between 1 and 12 then
    raise exception '닉네임을 확인해주세요.';
  end if;
  select * into rec from public.rooms
  where code = upper(trim(p_code)) for update;
  if not found then raise exception '방 코드를 찾을 수 없습니다.'; end if;
  perform public.toong_guard(rec, false);
  select member_id into existing from public.room_members
  where room_id = rec.id and actor_id = auth.uid();
  -- 이미 참여한 방을 다시 여는 것은 입력이 아니므로 시각을 바꾸지 않는다.
  if existing is not null then return rec.data; end if;
  perform public.toong_guard(rec, true);
  payload := jsonb_set(rec.data, '{members}',
    (rec.data->'members') || jsonb_build_array(jsonb_build_object(
      'id', mid::text, 'name', trim(p_nickname), 'actor_id', auth.uid()::text)));
  payload := payload || jsonb_build_object(
    'version', rec.version + 1, 'last_activity_at', stamp);
  update public.rooms
  set data = payload, version = rec.version + 1, last_activity_at = stamp
  where id = rec.id;
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
  stamp timestamptz := now();
  payload jsonb;
begin
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 수정할 수 있습니다.';
  end if;
  perform public.toong_guard(rec, true);
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
         -- 괄호가 없으면 (valid_ids @> item) -> 'member_ids'로 읽혀 저장이 실패한다.
         not valid_ids @> (item->'member_ids') or
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
  -- 마지막 입력 시각과 연장·얼림·완료 상태는 서버가 정한다. 앱이 보낸 값은 덮어쓴다.
  payload := p_data || jsonb_build_object(
    'version', rec.version + 1, 'last_activity_at', stamp,
    'extend_count', coalesce(rec.data->'extend_count', '0'::jsonb),
    'frozen_at', rec.data->'frozen_at',
    'completed_at', rec.data->'completed_at');
  update public.rooms
  set data = payload, version = rec.version + 1, last_activity_at = stamp
  where id = rec.id;
  return payload;
end;
$$;

create or replace function public.clone_toong_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  source public.rooms%rowtype;
  my_member uuid;
  rid uuid := gen_random_uuid();
  stamp timestamptz := now();
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
  -- 얼린 방과 완료된 방도 복제할 수 있다.
  perform public.toong_guard(source, false);
  select jsonb_agg(jsonb_set(m, '{actor_id}',
    case when m->>'id' = my_member::text then to_jsonb(auth.uid()::text)
    else 'null'::jsonb end)) into copied_members
  from jsonb_array_elements(source.data->'members') m;
  loop
    attempt := attempt + 1;
    if attempt > 10 then raise exception '방 코드 생성에 실패했습니다.'; end if;
    room_code := public.toong_code();
    -- 복제본은 새 방이므로 48시간을 새로 세고, 연장·얼림·완료 상태를 물려받지 않는다.
    payload := source.data || jsonb_build_object(
      'id', rid::text, 'code', room_code,
      'name', left((source.data->>'name') || ' 복제', 30),
      'owner_member_id', my_member::text, 'members', copied_members,
      'version', 0, 'source_room_id', source.id::text,
      'last_activity_at', stamp,
      'extend_count', 0, 'frozen_at', null, 'completed_at', null);
    begin
      insert into public.rooms(
        id, code, owner_actor, source_room_id, data, last_activity_at)
      values(rid, room_code, auth.uid(), source.id, payload, stamp);
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
  stamp timestamptz := now();
  payload jsonb;
begin
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 기록을 연결할 수 있습니다.';
  end if;
  perform public.toong_guard(rec, true);
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
  payload := payload || jsonb_build_object(
    'version', rec.version + 1, 'last_activity_at', stamp);
  delete from public.room_members where room_id = p_room_id and member_id = p_joined_id;
  insert into public.room_members(room_id, actor_id, member_id)
  values(p_room_id, joined_actor, p_historical_id);
  update public.rooms
  set data = payload, version = rec.version + 1, last_activity_at = stamp
  where id = rec.id;
  return payload;
end;
$$;

-- 방 연장: 남은 시간을 48시간으로 되돌린다. 방 하나당 3회, 방장만.
create or replace function public.extend_toong_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
  used integer;
  stamp timestamptz := now();
  payload jsonb;
begin
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 할 수 있어요.';
  end if;
  perform public.toong_guard(rec, true);
  used := coalesce((rec.data->>'extend_count')::integer, 0);
  if used >= 3 then
    raise exception '이 방은 더 연장할 수 없어요. (최대 3회)';
  end if;
  payload := rec.data || jsonb_build_object(
    'version', rec.version + 1, 'last_activity_at', stamp,
    'extend_count', used + 1);
  update public.rooms
  set data = payload, version = rec.version + 1, last_activity_at = stamp
  where id = rec.id;
  return payload;
end;
$$;

-- 방 얼리기: 삭제 시간을 멈춘다. 한 사람이 동시에 2개까지, 방장만.
create or replace function public.freeze_toong_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
  frozen integer;
  payload jsonb;
begin
  -- 같은 사람이 여러 방을 동시에 얼려 제한을 넘기지 못하게 한다.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 할 수 있어요.';
  end if;
  perform public.toong_guard(rec, true);
  select count(*) into frozen from public.rooms
  where owner_actor = auth.uid() and data->>'frozen_at' is not null
    and expires_at > now();
  if frozen >= 2 then
    raise exception '방은 동시에 2개까지만 얼릴 수 있어요.';
  end if;
  payload := rec.data || jsonb_build_object(
    'version', rec.version + 1, 'frozen_at', now());
  update public.rooms set data = payload, version = rec.version + 1
  where id = rec.id;
  return payload;
end;
$$;

-- 녹이기: 그때부터 48시간을 다시 센다.
create or replace function public.thaw_toong_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
  stamp timestamptz := now();
  payload jsonb;
begin
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 할 수 있어요.';
  end if;
  perform public.toong_guard(rec, false);
  if rec.data->>'frozen_at' is null then
    raise exception '얼린 방이 아니에요.';
  end if;
  payload := rec.data || jsonb_build_object(
    'version', rec.version + 1, 'last_activity_at', stamp, 'frozen_at', null);
  update public.rooms
  set data = payload, version = rec.version + 1, last_activity_at = stamp
  where id = rec.id;
  return payload;
end;
$$;

-- 정산 완료: 더 이상 수정할 수 없고 12시간 뒤 삭제된다. 방장만.
-- 기록은 서버에 따로 저장하지 않는다. 참여자 앱이 방을 열 때 기기에 저장한다.
create or replace function public.complete_toong_room(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
  payload jsonb;
begin
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 할 수 있어요.';
  end if;
  perform public.toong_guard(rec, true);
  if jsonb_array_length(rec.data->'expenses') = 0 then
    raise exception '지출이 없는 방은 정산을 완료할 수 없어요.';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(rec.data->'expenses') e,
         jsonb_array_elements(e->'items') i
    where (i->>'amount')::numeric % jsonb_array_length(i->'member_ids') <> 0
      and i->>'remainder_member_id' is null
  ) then
    raise exception '남은 잔돈의 부담자를 먼저 정해주세요.';
  end if;
  payload := rec.data || jsonb_build_object(
    'version', rec.version + 1, 'completed_at', now());
  update public.rooms set data = payload, version = rec.version + 1
  where id = rec.id;
  return payload;
end;
$$;

-- 삭제 시각이 지난 방을 지운다. 지운 방 수를 돌려준다.
create or replace function public.delete_expired_toong_rooms()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  removed integer;
begin
  delete from public.rooms where expires_at <= now();
  get diagnostics removed = row_count;
  return removed;
end;
$$;

-- 참여 중인 방이 하나도 없는 익명 사용자를 지운다. 막 만들어진 사용자가
-- 방을 만들기 전에 지워지지 않도록 48시간이 지난 사용자만 대상으로 한다.
create or replace function public.delete_orphan_toong_users()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  removed integer;
begin
  delete from auth.users u
  where u.is_anonymous
    and u.created_at <= now() - interval '48 hours'
    and not exists (select 1 from public.room_members m where m.actor_id = u.id)
    and not exists (select 1 from public.rooms r where r.owner_actor = u.id);
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.toong_set_expiry() from public, anon, authenticated;
revoke all on function public.toong_guard(public.rooms, boolean) from public, anon, authenticated;
revoke all on function public.toong_require_user() from public, anon, authenticated;
revoke all on function public.delete_expired_toong_rooms() from public, anon, authenticated;
revoke all on function public.delete_orphan_toong_users() from public, anon, authenticated;
revoke all on function public.extend_toong_room(uuid) from public, anon;
revoke all on function public.freeze_toong_room(uuid) from public, anon;
revoke all on function public.thaw_toong_room(uuid) from public, anon;
revoke all on function public.complete_toong_room(uuid) from public, anon;
grant execute on function public.extend_toong_room(uuid) to authenticated;
grant execute on function public.freeze_toong_room(uuid) to authenticated;
grant execute on function public.thaw_toong_room(uuid) to authenticated;
grant execute on function public.complete_toong_room(uuid) to authenticated;

-- 방 정리는 1시간마다(기존 작업), 익명 사용자 정리는 하루 한 번.
select cron.schedule(
  'toong-delete-orphan-users',
  '17 19 * * *',
  $cron$select public.delete_orphan_toong_users()$cron$
);
