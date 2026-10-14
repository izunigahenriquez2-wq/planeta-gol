-- Comprueba las probabilidades y las garantías del sorteo (6000 sobres y una racha de 4000). Se revierte solo.
-- Esperado cartas 1-4: 58.5 / 28.0 / 10.0 / 3.0 / 0.5 %  ·  carta 5: 0 / 67.5 / 24.1 / 7.2 / 1.2 %
-- Racha máxima sin Épica ≤ 14 y sin Legendaria ≤ 59.
do $$
declare txt text := ''; rec record; i int; j jsonb; mx int; se int := 0; sl int := 0; max_se int := 0; max_sl int := 0; tot4 numeric; tot1 numeric;
begin
  create temp table muestra on commit drop as
    select (e->>'r')::int as ra, ord from generate_series(1, 6000) g, lateral jsonb_array_elements(public._sortear_sobre(g - g, g - g)) with ordinality as t(e, ord);
  select count(*) into tot4 from muestra where ord < 5; select count(*) into tot1 from muestra where ord = 5;
  for rec in select ra, count(*) c from muestra where ord < 5 group by ra order by ra loop txt := txt || 'cartas 1-4 rareza ' || rec.ra || ': ' || round(100 * rec.c / tot4, 2) || ' %' || E'\n'; end loop;
  for rec in select ra, count(*) c from muestra where ord = 5 group by ra order by ra loop txt := txt || 'carta 5 rareza ' || rec.ra || ': ' || round(100 * rec.c / tot1, 2) || ' %' || E'\n'; end loop;
  for i in 1..4000 loop
    j := public._sortear_sobre(se, sl); select max((e->>'r')::int) into mx from jsonb_array_elements(j) e;
    if mx >= 3 then se := 0; else se := se + 1; end if; if mx >= 4 then sl := 0; else sl := sl + 1; end if;
    max_se := greatest(max_se, se); max_sl := greatest(max_sl, sl);
  end loop;
  txt := txt || 'racha máxima sin Épica: ' || max_se || ' · sin Legendaria: ' || max_sl;
  raise exception E'RESULTADOS (todo se revierte):\n%', txt;
end $$;
