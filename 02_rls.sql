-- =====================================================================
-- 02 · Seguridad: funciones, RLS y grants (schema callcenter)
-- =====================================================================
-- Exponer el schema por la API (Project Settings → API → Exposed schemas: agregar "callcenter").
grant usage on schema callcenter to authenticated, anon;

-- Funciones security definer (evitan recursión de RLS sobre perfiles)
create or replace function callcenter.mi_rol() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select rol from callcenter.perfiles where id = auth.uid() and activo), 'pendiente');
$$;
create or replace function callcenter.mi_agente() returns text
language sql stable security definer set search_path = public as $$
  select agente from callcenter.perfiles where id = auth.uid() and activo;
$$;
create or replace function callcenter.puedo_cargar() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (puede_cargar or rol = 'admin') from callcenter.perfiles where id = auth.uid() and activo), false);
$$;
create or replace function callcenter.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select callcenter.mi_rol() = 'admin';
$$;
create or replace function callcenter.es_jefa() returns boolean
language sql stable security definer set search_path = public as $$
  select callcenter.mi_rol() in ('admin','jefa');
$$;

-- Trigger: una ejecutiva solo puede cambiar sus columnas de respuesta
create or replace function callcenter.proteger_origen()
returns trigger language plpgsql as $$
begin
  if callcenter.mi_rol() = 'ejecutiva' then
    if (new.id_lead, new.tipo, new.periodo, new.agente, new.carga_id, new.producto, new.nombre, new.apellido, new.doc,
        new.cel, new.tel, new.email, new.creado, new.asignado_a, new.sucursal, new.vendedor, new.jefe, new.local)
       is distinct from
       (old.id_lead, old.tipo, old.periodo, old.agente, old.carga_id, old.producto, old.nombre, old.apellido, old.doc,
        old.cel, old.tel, old.email, old.creado, old.asignado_a, old.sucursal, old.vendedor, old.jefe, old.local) then
      raise exception 'Solo puedes modificar las respuestas del lead';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists cc_proteger_origen on callcenter.leads;
create trigger cc_proteger_origen before update on callcenter.leads
  for each row execute function callcenter.proteger_origen();

-- ---------- RLS ----------
alter table callcenter.perfiles  enable row level security;
alter table callcenter.vendedores enable row level security;
alter table callcenter.ajustes   enable row level security;
alter table callcenter.cargas    enable row level security;
alter table callcenter.leads     enable row level security;

-- perfiles: cada uno ve el suyo; admin ve y edita todos
drop policy if exists perfiles_sel on callcenter.perfiles;
create policy perfiles_sel on callcenter.perfiles for select to authenticated
  using (id = auth.uid() or callcenter.es_admin());
drop policy if exists perfiles_upd on callcenter.perfiles;
create policy perfiles_upd on callcenter.perfiles for update to authenticated
  using (callcenter.es_admin()) with check (callcenter.es_admin());

-- vendedores y ajustes: todos leen; jefa/admin escriben
drop policy if exists vend_sel on callcenter.vendedores;
create policy vend_sel on callcenter.vendedores for select to authenticated using (true);
drop policy if exists vend_all on callcenter.vendedores;
create policy vend_all on callcenter.vendedores for all to authenticated
  using (callcenter.es_jefa()) with check (callcenter.es_jefa());
drop policy if exists aj_sel on callcenter.ajustes;
create policy aj_sel on callcenter.ajustes for select to authenticated using (true);
drop policy if exists aj_all on callcenter.ajustes;
create policy aj_all on callcenter.ajustes for all to authenticated
  using (callcenter.es_jefa()) with check (callcenter.es_jefa());

-- cargas: todos leen; quien puede cargar inserta/borra
drop policy if exists cargas_sel on callcenter.cargas;
create policy cargas_sel on callcenter.cargas for select to authenticated using (true);
drop policy if exists cargas_ins on callcenter.cargas;
create policy cargas_ins on callcenter.cargas for insert to authenticated with check (callcenter.puedo_cargar());
drop policy if exists cargas_del on callcenter.cargas;
create policy cargas_del on callcenter.cargas for delete to authenticated using (callcenter.puedo_cargar());

-- leads: ejecutiva solo los suyos; jefa/admin todos
drop policy if exists leads_sel on callcenter.leads;
create policy leads_sel on callcenter.leads for select to authenticated
  using (callcenter.es_jefa() or agente = callcenter.mi_agente());
drop policy if exists leads_upd on callcenter.leads;
create policy leads_upd on callcenter.leads for update to authenticated
  using (callcenter.es_admin() or agente = callcenter.mi_agente())
  with check (callcenter.es_admin() or agente = callcenter.mi_agente());
drop policy if exists leads_ins on callcenter.leads;
create policy leads_ins on callcenter.leads for insert to authenticated with check (callcenter.puedo_cargar());
drop policy if exists leads_del on callcenter.leads;
create policy leads_del on callcenter.leads for delete to authenticated using (callcenter.puedo_cargar());

-- ---------- Grants explícitos (Supabase no los da solos) ----------
grant select, insert, update, delete on all tables in schema callcenter to authenticated;
grant usage, select on all sequences in schema callcenter to authenticated;
alter default privileges in schema callcenter grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema callcenter grant usage, select on sequences to authenticated;
grant execute on all functions in schema callcenter to authenticated;

-- ---------- Resumen por vendedor (opcional, para BI) ----------
create or replace view callcenter.v_resumen_vendedor with (security_invoker = true) as
select periodo, tipo, vendedor, local,
  count(*) as leads,
  count(*) filter (where upper(cc) = 'SI') as contactado,
  count(*) filter (where upper(cc) = 'NO') as no_contesta,
  count(*) filter (where coalesce(cc,'') = '') as pendiente,
  count(*) filter (where upper(ffvv) = 'SI') as ffvv_si,
  count(*) filter (where upper(ppto) = 'SI') as ppto_si,
  count(*) filter (where upper(sigue) = 'SI') as sigue_si,
  count(*) filter (where upper(explico) = 'SI') as explico_si,
  count(*) filter (where upper(invito) = 'SI') as invito_si,
  count(*) filter (where upper(estado) = 'RESCATADO') as rescatado
from callcenter.leads group by 1,2,3,4;
grant select on callcenter.v_resumen_vendedor to authenticated;

-- ---------- RPC para la carga (quien carga no ve los leads de las demás, pero sí necesita esto) ----------
create or replace function callcenter.ids_existentes(ids text[]) returns setof text
language sql stable security definer set search_path = public as $$
  select id_lead from callcenter.leads where id_lead = any(ids) and callcenter.puedo_cargar();
$$;
create or replace function callcenter.conteo_periodo(p text) returns table (tipo text, agente text, n bigint)
language sql stable security definer set search_path = public as $$
  select tipo, agente, count(*) from callcenter.leads where periodo = p and callcenter.puedo_cargar() group by 1,2;
$$;
create or replace function callcenter.periodos() returns setof text
language sql stable security definer set search_path = public as $$
  select distinct periodo from callcenter.leads order by 1 desc;
$$;
grant execute on all functions in schema callcenter to authenticated;
