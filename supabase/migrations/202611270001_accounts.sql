-- 송금받을 계좌. 참여자마다 은행·계좌번호·예금주를 방에 등록해 보내는 사람이 송금할 때 쓴다.
-- Run after 202611260001_paid_transfers.sql.
--
-- 방 data의 accounts에 {"<member_id>": {bank, number, holder, by, at}}로 저장한다.
-- 본인만 자기 계좌를 바꿀 수 있고, 앱 없이 방장이 추가한(미연결) 사람의 계좌는 방장이 넣는다.
-- save_toong_room은 이 값을 앱이 바꾸지 못하게 서버 값을 유지하고, 복제한 방은 비운다.
-- 방이 삭제되면 계좌도 함께 사라진다. 계좌 등록은 삭제 시간을 늘리지 않는다.

update public.rooms set data = data || '{"accounts": {}}'::jsonb
where not data ? 'accounts';

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
  -- 마지막 입력 시각과 연장·얼림·완료 상태, 송금 완료 표시, 계좌는 서버가 정한다. 앱이 보낸 값은 덮어쓴다.
  payload := p_data || jsonb_build_object(
    'version', rec.version + 1, 'last_activity_at', stamp,
    'extend_count', coalesce(rec.data->'extend_count', '0'::jsonb),
    'frozen_at', rec.data->'frozen_at',
    'completed_at', rec.data->'completed_at',
    'paid_transfers', coalesce(rec.data->'paid_transfers', '[]'::jsonb),
    'accounts', coalesce(rec.data->'accounts', '{}'::jsonb));
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
    -- 복제본은 새 방이므로 48시간을 새로 세고, 연장·얼림·완료 상태, 송금 완료 표시, 계좌를 물려받지 않는다.
    payload := source.data || jsonb_build_object(
      'id', rid::text, 'code', room_code,
      'name', left((source.data->>'name') || ' 복제', 30),
      'owner_member_id', my_member::text, 'members', copied_members,
      'version', 0, 'source_room_id', source.id::text,
      'last_activity_at', stamp,
      'extend_count', 0, 'frozen_at', null, 'completed_at', null,
      'paid_transfers', '[]'::jsonb, 'accounts', '{}'::jsonb);
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
  -- 뺀 사람의 계좌도 지운다.
  payload := payload || jsonb_build_object(
    'accounts', coalesce(rec.data->'accounts', '{}'::jsonb) - p_member_id,
    'version', rec.version + 1, 'last_activity_at', stamp);
  delete from public.room_members
  where room_id = rec.id and member_id::text = p_member_id;
  update public.rooms
  set data = payload, version = rec.version + 1, last_activity_at = stamp
  where id = rec.id;
  return payload;
end;
$$;

create or replace function public.set_toong_account(
  p_room_id uuid, p_member_id text, p_bank text, p_number text, p_holder text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
  me uuid;
  target jsonb;
  digits text;
  holder text := btrim(coalesce(p_holder, ''));
  accounts jsonb;
  payload jsonb;
begin
  perform public.toong_require_user();
  select * into rec from public.rooms where id = p_room_id for update;
  if not found then raise exception '방을 찾을 수 없어요.'; end if;
  -- 얼린 방과 완료된 방에서도 등록할 수 있다(정산이 끝난 뒤 송금하는 경우가 많다).
  perform public.toong_guard(rec, false);
  select member_id into me from public.room_members
  where room_id = rec.id and actor_id = auth.uid();
  if me is null then raise exception '참여 중인 방만 계좌를 등록할 수 있어요.'; end if;
  select m into target from jsonb_array_elements(rec.data->'members') m
  where m->>'id' = p_member_id;
  if target is null then raise exception '방에 없는 참여자예요.'; end if;
  if me::text <> p_member_id and not (
       rec.owner_actor = auth.uid() and coalesce(target->>'actor_id', '') = '') then
    raise exception '본인 계좌만 등록할 수 있어요. 앱 없이 추가한 사람은 방장이 넣을 수 있어요.';
  end if;
  accounts := coalesce(rec.data->'accounts', '{}'::jsonb);
  if p_bank is null then
    accounts := accounts - p_member_id;
  else
    digits := regexp_replace(coalesce(p_number, ''), '-', '', 'g');
    if p_bank not in ('kb','shinhan','woori','hana','nh','nhlocal','ibk','kakao','toss','kbank','sc','citi','suhyup','mg','cu','epost','busan','kyongnam','im','kj','jb','jeju','kdb','savings','sanlim') or
       coalesce(p_number, '') !~ '^[0-9-]{8,24}$' or
       length(digits) not between 8 and 20 or
       length(holder) not between 1 and 20 then
      raise exception '은행, 계좌번호(숫자 8~20자리), 예금주(20자 이내)를 확인해주세요.';
    end if;
    accounts := accounts || jsonb_build_object(p_member_id, jsonb_build_object(
      'bank', p_bank, 'number', p_number, 'holder', holder,
      'by', me::text, 'at', now()));
  end if;
  payload := rec.data || jsonb_build_object(
    'accounts', accounts, 'version', rec.version + 1);
  update public.rooms set data = payload, version = rec.version + 1 where id = rec.id;
  return payload;
end;
$$;

revoke all on function public.set_toong_account(uuid, text, text, text, text) from public, anon;
grant execute on function public.set_toong_account(uuid, text, text, text, text) to authenticated;
