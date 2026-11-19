-- 방장이 참여 중인 방 목록에서 방을 바로 삭제한다.
-- Run after 202611150001_receipt_scan.sql.
--
-- 참여자 정보(room_members)는 외래 키로 함께 지워지고, 이 방을 복제한 방의
-- source_room_id는 null이 된다. 완료된 정산 기록은 각자 기기에 남아 있다.
create or replace function public.delete_toong_room(p_room_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  rec public.rooms%rowtype;
begin
  perform public.toong_require_user();
  select * into rec from public.rooms where id = p_room_id for update;
  if not found or rec.owner_actor is distinct from auth.uid() then
    raise exception '방장만 방을 삭제할 수 있어요.';
  end if;
  delete from public.rooms where id = rec.id;
end;
$$;

revoke all on function public.delete_toong_room(uuid) from public, anon;
grant execute on function public.delete_toong_room(uuid) to authenticated;
