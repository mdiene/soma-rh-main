-- Retour : remet la source IFC_INTERIM à son état provisoire d'avant la lecture du décret et retire DEC_2009_1412.
update public.legal_sources
   set label = 'Indemnité de fin de mission d''intérim : 7 % provisoire',
       source_type = 'A_FOURNIR',
       document = 'Décret 2009-1412 (non lu) ; Code 2026 art. 292-293',
       article = '292-293',
       status = 'a_confirmer',
       notes = 'Valeur issue de sources secondaires qui alignent l''intérim sur le CDD.'
 where code = 'IFC_INTERIM';
delete from public.legal_sources where code = 'DEC_2009_1412';
comment on column public.payroll_settings.interim_ifc_rate is null;
notify pgrst, 'reload schema';
