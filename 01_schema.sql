-- =====================================================================
-- 01 · Esquema CALL CENTER (rescate de leads) · DITALCAR
-- Idempotente: se puede ejecutar más de una vez en el SQL Editor.
-- Convive con la plataforma de seguimiento: todo va en el schema "callcenter".
-- =====================================================================
create schema if not exists callcenter;

-- ---------- Perfiles (1 fila por usuario de Supabase Auth) ----------
create table if not exists callcenter.perfiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text,
  nombre        text,
  rol           text not null default 'pendiente' check (rol in ('pendiente','admin','jefa','ejecutiva')),
  agente        text check (agente in ('camila','millaray','katherine','mariajose')),
  puede_cargar  boolean not null default false,
  activo        boolean not null default true,
  creado_el     timestamptz not null default now()
);

-- Trigger: al crear un usuario en Auth se crea su perfil (rol pendiente)
create or replace function callcenter.crear_perfil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into callcenter.perfiles (id, email) values (new.id, new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end $$;
drop trigger if exists cc_crear_perfil on auth.users;
create trigger cc_crear_perfil after insert on auth.users
  for each row execute function callcenter.crear_perfil();

-- Perfiles para usuarios que ya existían antes de este script
insert into callcenter.perfiles (id, email)
select u.id, u.email from auth.users u
on conflict (id) do nothing;

-- ---------- Maestro de vendedores (alias Pilot → nombre único) ----------
create table if not exists callcenter.vendedores (
  id        bigserial primary key,
  alias     text not null,
  nombre    text not null,
  sucursal  text default '',
  jefe      text default '',
  constraint vendedores_alias_unico unique (alias)
);

-- ---------- Ajustes (clave/valor jsonb) ----------
create table if not exists callcenter.ajustes (
  clave  text primary key,
  valor  jsonb not null,
  actualizado_el timestamptz not null default now()
);

-- ---------- Log de cargas ----------
create table if not exists callcenter.cargas (
  id        bigserial primary key,
  fecha     timestamptz not null default now(),
  usuario   uuid references auth.users(id),
  archivo   text,
  total     int not null default 0,
  asig      jsonb,
  dupes     int not null default 0,
  excluidos int not null default 0,
  periodos  text[]
);

-- ---------- Leads ----------
create table if not exists callcenter.leads (
  id_lead        text primary key,                 -- 'P'+ID Pilot (o 'R'+ID Remoto)
  tipo           text not null check (tipo in ('NUEVO','SEMINUEVO')),
  periodo        text not null,                    -- 'YYYY-MM' de "Creado el"
  agente         text not null check (agente in ('camila','millaray','katherine','mariajose')),
  carga_id       bigint references callcenter.cargas(id) on delete cascade,
  -- datos de Pilot
  estado_lead text, vendido text, producto text, nombre text, apellido text, doc text,
  tel text, cel text, email text, negocio text, origen text, suborigen text, notas text,
  creado timestamptz, asignado_el timestamptz, asignado_a text, sucursal text, interes text,
  desistido_el timestamptz, desistido_por text, motivo_desistido text, notas_desistido text,
  vendedor text, jefe text, local text, costanera boolean not null default false,
  extra jsonb,
  -- respuestas del call center (preguntas X..AI de la planilla)
  cc text, ffvv text, ppto text, cot text, sigue text, explico text, entendio text, invito text,
  estado text, motivo_r text, motivo_nr text, comentario text,
  gestionado_el  timestamptz,
  gestionado_por uuid,
  creado_registro timestamptz not null default now()
);
create index if not exists leads_periodo_agente on callcenter.leads (periodo, agente);
create index if not exists leads_periodo_tipo   on callcenter.leads (periodo, tipo);
create index if not exists leads_carga          on callcenter.leads (carga_id);

-- Trigger: marca quién y cuándo gestionó una respuesta
create or replace function callcenter.marcar_gestion()
returns trigger language plpgsql as $$
begin
  if (new.cc, new.ffvv, new.ppto, new.cot, new.sigue, new.explico, new.entendio, new.invito, new.estado, new.motivo_r, new.motivo_nr, new.comentario)
     is distinct from
     (old.cc, old.ffvv, old.ppto, old.cot, old.sigue, old.explico, old.entendio, old.invito, old.estado, old.motivo_r, old.motivo_nr, old.comentario) then
    new.gestionado_el := now();
    new.gestionado_por := auth.uid();
  end if;
  return new;
end $$;
drop trigger if exists cc_marcar_gestion on callcenter.leads;
create trigger cc_marcar_gestion before update on callcenter.leads
  for each row execute function callcenter.marcar_gestion();

-- ---------- Ajustes por defecto ----------
insert into callcenter.ajustes (clave, valor) values
 ('objetivo', '0.95'),
 ('exclusiones', '{"negocios":["Campañas Automáticas"],"sucursales":[]}'),
 ('scoring', '[
   {"k":"pFfvv","t":"Contactado x vendedor","peso":40,"ok":0.845,"medOk":0.844,"medBad":0.495,"bad":0.494},
   {"k":"pPpto","t":"Ppto enviado","peso":7.5,"ok":0.795,"medOk":0.794,"medBad":0.495,"bad":0.494},
   {"k":"pSigue","t":"Sigue en contacto","peso":15,"ok":0.795,"medOk":0.794,"medBad":0.495,"bad":0.494},
   {"k":"pExplico","t":"Ppto explicado","peso":7.5,"ok":0.795,"medOk":0.794,"medBad":0.495,"bad":0.494},
   {"k":"pInvito","t":"Invitó al local","peso":10,"ok":0.795,"medOk":0.794,"medBad":0.495,"bad":0.494},
   {"k":"pResc","t":"Rescatado (inverso)","peso":20,"ok":0.035,"medOk":0.034,"medBad":0.1945,"bad":0.1946,"inverso":true}
 ]')
on conflict (clave) do nothing;
