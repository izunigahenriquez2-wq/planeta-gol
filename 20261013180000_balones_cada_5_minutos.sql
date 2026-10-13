-- Balones de Oro: 1 cada 5 minutos con la página abierta, SIN límite diario.
-- (tope_diario = NULL significa "sin límite"; se puede volver a poner un tope con admin_configurar_balones)
alter table public.balones_config alter column tope_diario drop not null;
alter table public.balones_config drop constraint if exists balones_config_tope_diario_check;
alter table public.balones_config add constraint balones_config_tope_diario_check
  check (tope_diario is null or tope_diario between 1 and 1000000);
update public.balones_config set segundos_por_balon = 300, tope_diario = null where id;

create or replace function public.registrar_latido()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  c public.balones_config%rowtype;
  a public.actividad%rowtype;
  v_now timestamptz := now();
  v_dia date;
  v_elapsed numeric;
  v_credito integer := 0;
  v_ganados integer := 0;
begin
  if v_uid is null then raise exception 'NO_AUTENTICADO' using errcode = '28000'; end if;
  if not exists (select 1 from public.profiles where id = v_uid) then raise exception 'PERFIL_INCOMPLETO'; end if;
  select * into c from public.balones_config where id;
  v_dia := (v_now at time zone c.zona_horaria)::date;
  insert into public.actividad (user_id, dia) values (v_uid, v_dia) on conflict (user_id) do nothing;
  select * into a from public.actividad where user_id = v_uid for update;
  if a.dia <> v_dia then a.dia := v_dia; a.balones_hoy := 0; end if;
  if a.ultimo_latido is null then
    a.ultimo_latido := v_now;
  else
    v_elapsed := extract(epoch from (v_now - a.ultimo_latido));
    if v_elapsed >= c.intervalo_minimo then
      v_credito := least(floor(v_elapsed)::integer, c.credito_maximo);
      a.ultimo_latido := v_now;
    end if;
  end if;
  if c.tope_diario is not null and a.balones_hoy >= c.tope_diario then
    a.segundos := 0;
  else
    a.segundos := a.segundos + v_credito;
    while a.segundos >= c.segundos_por_balon and (c.tope_diario is null or a.balones_hoy < c.tope_diario) loop
      a.segundos := a.segundos - c.segundos_por_balon;
      a.balones_hoy := a.balones_hoy + 1;
      v_ganados := v_ganados + 1;
    end loop;
    if c.tope_diario is not null and a.balones_hoy >= c.tope_diario then a.segundos := 0; end if;
  end if;
  update public.actividad set ultimo_latido = a.ultimo_latido, segundos = a.segundos, dia = a.dia, balones_hoy = a.balones_hoy
    where user_id = v_uid;
  if v_ganados > 0 then perform public._acreditar_balones(v_uid, v_ganados); end if;
  return jsonb_build_object('ganados', v_ganados, 'segundos', a.segundos, 'por_balon', c.segundos_por_balon,
                            'hoy', a.balones_hoy, 'tope', c.tope_diario);
end;
$$;
revoke all on function public.registrar_latido() from public, anon, authenticated;
grant execute on function public.registrar_latido() to authenticated;

create or replace function public.mi_progreso()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); c public.balones_config%rowtype; a public.actividad%rowtype; v_dia date;
begin
  if v_uid is null then raise exception 'NO_AUTENTICADO' using errcode = '28000'; end if;
  select * into c from public.balones_config where id;
  v_dia := (now() at time zone c.zona_horaria)::date;
  select * into a from public.actividad where user_id = v_uid;
  return jsonb_build_object('segundos', coalesce(a.segundos, 0), 'por_balon', c.segundos_por_balon,
    'hoy', case when a.dia = v_dia then a.balones_hoy else 0 end, 'tope', c.tope_diario);
end;
$$;
revoke all on function public.mi_progreso() from public, anon, authenticated;
grant execute on function public.mi_progreso() to authenticated;

-- Configuración segura (solo service_role / SQL Editor). Ejemplos:
--   select public.admin_configurar_balones(300);                 -- 1 Balón cada 5 min
--   select public.admin_configurar_balones(null, 20);            -- tope de 20 al día
--   select public.admin_configurar_balones(null, null, true);    -- sin tope
drop function if exists public.admin_configurar_balones(integer, integer);
create or replace function public.admin_configurar_balones(p_segundos_por_balon integer default null, p_tope_diario integer default null, p_sin_tope boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.balones_config set
    segundos_por_balon = coalesce(p_segundos_por_balon, segundos_por_balon),
    tope_diario        = case when p_sin_tope then null else coalesce(p_tope_diario, tope_diario) end
  where id;
end;
$$;
revoke all on function public.admin_configurar_balones(integer, integer, boolean) from public, anon, authenticated;
grant execute on function public.admin_configurar_balones(integer, integer, boolean) to service_role;
