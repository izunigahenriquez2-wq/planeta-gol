-- Pruebas de SOBRES, reciclaje y alineación. TODO se revierte al final (excepción a propósito).
-- El resultado aparece en el mensaje de error "RESULTADOS (todo se revierte)". Cada línea debe terminar en (OK).
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); txt text := ''; j jsonb; n int; ok boolean;
  cb int; st int;
begin
  insert into auth.users (id, email, raw_user_meta_data) values (a, 'sobres_a@example.test', '{"username":"Sobres_A"}'::jsonb);
  insert into auth.users (id, email, raw_user_meta_data) values (b, 'sobres_b@example.test', '{"username":"Sobres_B"}'::jsonb);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.abrir_sobre(); txt := txt || '1 sobre sin saldo: PERMITIDO (FALLO)' || E'\n';
  exception when others then txt := txt || '1 sobre con saldo 0: ' || sqlerrm || ' (OK)' || E'\n'; end;
  reset role; update public.balones_saldo set disponibles = 12 where user_id = a; set local role authenticated;
  j := public.abrir_sobre();
  txt := txt || '2 primer sobre: saldo ' || (j->>'saldo') || ' (OK si 7) | cartas=' || jsonb_array_length(j->'cartas') || E'\n';
  reset role;
  txt := txt || '2b copias=' || (select coalesce(sum(cantidad),0) from public.coleccion where user_id = a) || ' (OK si 5) | total histórico=' || (select total from public.balones_oro where user_id = a) || ' (OK si 0)' || E'\n';
  txt := txt || '2c alineación automática compatible: ' || (select bool_and(c.pos = s.pos or c.pos = any (s.flex)) from public.alineacion al join public.cartas c on c.id = al.carta_id join public.slots_433 s on s.slot = al.slot where al.user_id = a) || E'\n';
  update public.sobres_estado set sin_legendaria = 59 where user_id = a; update public.balones_saldo set disponibles = 20 where user_id = a; set local role authenticated;
  j := public.abrir_sobre(); reset role;
  select bool_or((x->>'r')::int = 4) into ok from jsonb_array_elements(j->'cartas') x;
  txt := txt || '3 garantía de Legendaria al sobre 60: ' || ok::text || E'\n';
  select id into cb from public.cartas where pos = 'CB' order by id limit 1;
  insert into public.coleccion (user_id, carta_id, cantidad) values (a, cb, 8) on conflict (user_id, carta_id) do update set cantidad = 8;
  update public.balones_saldo set disponibles = 4 where user_id = a; set local role authenticated;
  j := public.reciclar_repetidas(jsonb_build_array(jsonb_build_object('id', cb, 'n', 6)));
  txt := txt || '4 reciclar 6 repetidas: ' || j::text || ' (OK si +2 → saldo 6)' || E'\n';
  reset role; txt := txt || '4b total histórico sigue en ' || (select total from public.balones_oro where user_id = a) || ' (OK si 0)' || E'\n'; set local role authenticated;
  begin perform public.reciclar_repetidas(jsonb_build_array(jsonb_build_object('id', cb, 'n', 1))); txt := txt || '4c no múltiplo de 3: PERMITIDO (FALLO)' || E'\n';
  exception when others then txt := txt || '4c reciclar 1: ' || sqlerrm || ' (OK)' || E'\n'; end;
  begin perform public.reciclar_repetidas(jsonb_build_array(jsonb_build_object('id', cb, 'n', 3))); txt := txt || '4d más de las sobrantes: PERMITIDO (FALLO)' || E'\n';
  exception when others then txt := txt || '4d reciclar más de las sobrantes: ' || sqlerrm || ' (OK)' || E'\n'; end;
  perform public.poner_en_alineacion(2, cb); perform public.poner_en_alineacion(3, cb);
  txt := txt || '5a mover una carta de puesto: puestos ocupados=' || (select count(*) from public.alineacion where user_id = a and carta_id = cb) || ' (OK si 1)' || E'\n';
  begin perform public.poner_en_alineacion(0, cb); txt := txt || '5b defensa de portero: PERMITIDO (FALLO)' || E'\n';
  exception when others then txt := txt || '5b defensa en puesto de portero: ' || sqlerrm || ' (OK)' || E'\n'; end;
  reset role; perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true); set local role authenticated;
  txt := txt || '6a colección ajena visible: ' || (select count(*) from public.coleccion where user_id = a) || ' (OK si 0) | alineación ajena visible: ' || (select count(*) from public.alineacion where user_id = a) || ' (OK si > 0)' || E'\n';
  begin perform public._sortear_sobre(0, 0); txt := txt || '6b sorteo interno: PERMITIDO (FALLO)' || E'\n';
  exception when insufficient_privilege then txt := txt || '6b llamar al sorteo interno: denegado (OK)' || E'\n'; end;
  begin insert into public.alineacion (user_id, slot, carta_id) values (b, 0, 1); txt := txt || '6c escribir alineación directo: PERMITIDO (FALLO)' || E'\n';
  exception when insufficient_privilege then txt := txt || '6c escribir alineación directamente: denegado (OK)' || E'\n'; end;
  reset role;
  raise exception E'RESULTADOS (todo se revierte):\n%', txt;
end $$;
