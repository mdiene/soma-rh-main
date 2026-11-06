-- =============================================================================
-- Décret n° 2009-1412 du 23/12/2009 (JO du 27/03/2010, pp. 326-328) lu : travail temporaire.
-- IFC de l'intérim : 7 % des rémunérations brutes totales dues depuis le début du contrat, hors frais (art. 10) => confirmé.
-- Durée d'une mission et d'un contrat de travail temporaire : 2 ans (art. 4 et 8) ; caution >= 10 % du CA (art. 15).
-- Seules des lignes de référence changent : le moteur de paie n'est pas modifié (payroll_settings.interim_ifc_rate garde 7 %).
-- Retour : db/rollback/20261124090000_ifc_interim_decret_2009_1412_down.sql
-- =============================================================================
update public.legal_sources
   set label = 'Indemnité de fin de mission d''intérim : 7 % des rémunérations brutes',
       source_type = 'HERITEE',
       document = 'Décret 2009-1412 du 23/12/2009 (JO du 27/03/2010, p. 327)',
       article = '10',
       status = 'confirme',
       notes = 'Texte lu. 7 % des rémunérations totales brutes dues depuis le début du contrat, hors remboursements de frais. Non due : contrat d''une journée, saisonnier (campagne), docker, secteur d''usage sans CDI, refus d''un emploi CDI équivalent, faute lourde ou rupture anticipée à l''initiative du travailleur. Maintien sous le Code 2026 : art. 461.'
 where code = 'IFC_INTERIM';

insert into public.legal_sources (code, label, source_type, document, article, valid_from, status, notes) values
  ('DEC_2009_1412', 'Travail temporaire : contrat de mise à disposition, contrat de travail temporaire, contrôle', 'HERITEE',
   'Décret 2009-1412 du 23/12/2009 (JO du 27/03/2010, pp. 326-328)', '1-18', null, 'confirme',
   'Texte lu. Mission et contrat limités à 2 ans, sauf ouvrage déterminé (art. 4, 8) ; contrat de mise à disposition écrit, déposé en 5 exemplaires à l''Inspection (art. 2) ; attestation de régularité sociale (art. 3) ; interdiction de remplacer des grévistes licites (art. 12) ; caution d''au moins 10 % du chiffre d''affaires certifié (art. 15). Date d''entrée en vigueur non lue : art. 17 laisse six mois aux entreprises en activité.')
on conflict (code) do nothing;

comment on column public.payroll_settings.interim_ifc_rate is 'IFC intérim : 7 % (décret 2009-1412, art. 10, texte lu). Minimum légal : une valeur inférieure doit être signalée.';
notify pgrst, 'reload schema';
