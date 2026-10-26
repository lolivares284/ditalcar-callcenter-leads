-- 04 · Asignar roles a los usuarios creados en Authentication → Users (auto confirm).
-- Reemplaza los correos por los reales y ejecuta. También se puede hacer desde la pestaña Administración de la app.
update callcenter.perfiles set rol = 'admin',     nombre = 'Administrador'        where email = 'TU_CORREO@ditalcar.cl';
update callcenter.perfiles set rol = 'jefa',      nombre = 'Jefa Call Center'     where email = 'JEFA@ditalcar.cl';
update callcenter.perfiles set rol = 'ejecutiva', agente = 'camila',    puede_cargar = true,  nombre = 'Camila Asenjo'       where email = 'CAMILA@ditalcar.cl';
update callcenter.perfiles set rol = 'ejecutiva', agente = 'millaray',  puede_cargar = false, nombre = 'Millaray Muñoz'      where email = 'MILLARAY@ditalcar.cl';
update callcenter.perfiles set rol = 'ejecutiva', agente = 'katherine', puede_cargar = false, nombre = 'Katherine Rodríguez' where email = 'KATHERINE@ditalcar.cl';
update callcenter.perfiles set rol = 'ejecutiva', agente = 'mariajose', puede_cargar = false, nombre = 'María José Poblete'  where email = 'MARIAJOSE@ditalcar.cl';
select email, rol, agente, puede_cargar from callcenter.perfiles order by rol, agente;
