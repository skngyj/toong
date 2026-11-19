-- 2주차 영수증 인식(scan-receipt Edge Function)의 하루 사용 횟수.
-- Run after 202611110001_room_lifecycle.sql.
--
-- 서버에는 사용자별 하루 호출 횟수만 저장한다. 사진과 인식 결과는 저장하지 않는다.
-- 날짜는 한국 시간 기준이며, 이틀이 지난 기록은 매일 지운다.

create table if not exists public.scan_usage (
  actor_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  count integer not null default 0,
  primary key (actor_id, day)
);

alter table public.scan_usage enable row level security;
revoke all on public.scan_usage from anon, authenticated;

-- 호출 한 번을 센다. 오늘 한도(20회)를 넘으면 TG429로 거절한다.
-- 정리된 익명 사용자의 토큰이면 TG401로 거절한다(앱이 새 사용자로 다시 로그인).
create or replace function public.consume_toong_scan()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  today date := (now() at time zone 'Asia/Seoul')::date;
  used integer;
begin
  perform public.toong_require_user();
  insert into public.scan_usage(actor_id, day, count)
  values (auth.uid(), today, 1)
  on conflict (actor_id, day) do update set count = scan_usage.count + 1
  where scan_usage.count < 20
  returning count into used;
  if used is null then
    raise exception using errcode = 'TG429',
      message = '오늘은 영수증 인식을 20번까지 쓸 수 있어요. 직접 입력해주세요.';
  end if;
  return 20 - used;
end;
$$;

create or replace function public.delete_old_toong_scan_usage()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  removed integer;
begin
  delete from public.scan_usage
  where day < (now() at time zone 'Asia/Seoul')::date - 1;
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.consume_toong_scan() from public, anon;
grant execute on function public.consume_toong_scan() to authenticated;
revoke all on function public.delete_old_toong_scan_usage() from public, anon, authenticated;

select cron.schedule(
  'toong-delete-old-scan-usage',
  '23 19 * * *',
  $cron$select public.delete_old_toong_scan_usage()$cron$
);
