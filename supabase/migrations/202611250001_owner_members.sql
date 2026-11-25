-- 방장이 정산 인원을 직접 추가하거나 뺀다.
-- Run after 202611190001_delete_room.sql.
--
-- 추가한 사람은 앱 계정과 연결되지 않은 참여자(actor_id null)로 들어간다. 그 친구가
-- 나중에 방에 입장하면 방장이 `과거 참여자 기록 연결`로 합칠 수 있다.
-- 지출(결제자·부담자)에 들어간 사람과 방장은 뺄 수 없다. 앱으로 입장한 사람을 빼면
-- 그 사람은 이 방을 더 볼 수 없다.

create or replace function public.add_toong_member(p_room_id uuid, p_name text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
  clean text := trim(p_name);
  stamp timestamptz := now();
  payload jsonb;
begin
  perform public.toong_require_user();
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 사람을 추가할 수 있어요.';
  end if;
  perform public.toong_guard(rec, true);
  if length(clean) not between 1 and 12 then
    raise exception '이름은 1~12자로 입력해주세요.';
  end if;
  if jsonb_array_length(rec.data->'members') >= 30 then
    raise exception '한 방에는 30명까지 있을 수 있어요.';
  end if;
  if exists (select 1 from jsonb_array_elements(rec.data->'members') m
             where m->>'name' = clean) then
    raise exception '이미 같은 이름의 참여자가 있어요.';
  end if;
  payload := jsonb_set(rec.data, '{members}',
    (rec.data->'members') || jsonb_build_array(jsonb_build_object(
      'id', gen_random_uuid()::text, 'name', clean, 'actor_id', null)));
  payload := payload || jsonb_build_object(
    'version', rec.version + 1, 'last_activity_at', stamp);
  update public.rooms
  set data = payload, version = rec.version + 1, last_activity_at = stamp
  where id = rec.id;
  return payload;
end;
$$;

create or replace function public.remove_toong_member(p_room_id uuid, p_member_id text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
  stamp timestamptz := now();
  payload jsonb;
begin
  perform public.toong_require_user();
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 사람을 뺄 수 있어요.';
  end if;
  perform public.toong_guard(rec, true);
  if p_member_id = rec.data->>'owner_member_id' then
    raise exception '방장은 뺄 수 없어요.';
  end if;
  if not exists (select 1 from jsonb_array_elements(rec.data->'members') m
                 where m->>'id' = p_member_id) then
    raise exception '방에 없는 참여자예요.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(rec.data->'expenses') e
    where e->>'payer_id' = p_member_id
       or exists (select 1 from jsonb_array_elements(e->'items') i
                  where i->'member_ids' @> jsonb_build_array(p_member_id))) then
    raise exception '지출에 들어간 사람은 뺄 수 없어요. 먼저 지출에서 빼주세요.';
  end if;
  payload := jsonb_set(rec.data, '{members}', (
    select coalesce(jsonb_agg(m), '[]'::jsonb)
    from jsonb_array_elements(rec.data->'members') m
    where m->>'id' <> p_member_id));
  payload := payload || jsonb_build_object(
    'version', rec.version + 1, 'last_activity_at', stamp);
  delete from public.room_members
  where room_id = rec.id and member_id::text = p_member_id;
  update public.rooms
  set data = payload, version = rec.version + 1, last_activity_at = stamp
  where id = rec.id;
  return payload;
end;
$$;

revoke all on function public.add_toong_member(uuid, text) from public, anon;
revoke all on function public.remove_toong_member(uuid, text) from public, anon;
grant execute on function public.add_toong_member(uuid, text) to authenticated;
grant execute on function public.remove_toong_member(uuid, text) to authenticated;
