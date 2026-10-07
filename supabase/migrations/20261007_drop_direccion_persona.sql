-- Migración: Eliminar columna obsoleta 'direccion' de la tabla 'persona'
-- Las direcciones se gestionan dinámicamente en cada incidencia mediante 'direccion_texto' en la tabla 'reporte'.

ALTER TABLE public.persona DROP COLUMN IF EXISTS direccion;
