-- Le moteur de paie (compute_income_tax, compute_trimf) concorde avec les cas de validation du document de référence
-- « Moteur de calcul de paie — Sénégal (référentiel 2026) » fourni par le propriétaire (3 cas : IR mensuel et TRIMF mensuelle).
-- Lecture seule. Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/moteur_reference_2026.sql  (attendu : "OK moteur_reference_2026")
do $$
declare ir numeric; tr numeric;
begin
  -- cas 1 : non-cadre, brut imposable 350 000, 1 part IR, 1 part TRIMF -> IR 59 500, TRIMF 1 000
  ir := (public.compute_income_tax(350000, 1, date '2026-06-30')->>'monthly_tax')::numeric; tr := public.compute_trimf(350000, 1, date '2026-06-30');
  if round(ir) <> 59500 or round(tr) <> 1000 then raise exception 'cas 1 : IR % (attendu 59500), TRIMF % (attendu 1000)', round(ir), round(tr); end if;
  -- cas 2 : cadre, brut 1 200 000, 3 parts IR, 2 parts TRIMF -> IR 272 438, TRIMF 6 000
  ir := (public.compute_income_tax(1200000, 3, date '2026-06-30')->>'monthly_tax')::numeric; tr := public.compute_trimf(1200000, 2, date '2026-06-30');
  if round(ir) <> 272438 or round(tr) <> 6000 then raise exception 'cas 2 : IR % (attendu 272438), TRIMF % (attendu 6000)', round(ir), round(tr); end if;
  -- cas 3 (inverse) : brut trouvé 1 172 185, 2,5 parts IR, 2 parts TRIMF -> IR 282 361, TRIMF 6 000
  ir := (public.compute_income_tax(1172185, 2.5, date '2026-06-30')->>'monthly_tax')::numeric; tr := public.compute_trimf(1172185, 2, date '2026-06-30');
  if round(ir) <> 282361 or round(tr) <> 6000 then raise exception 'cas 3 : IR % (attendu 282361), TRIMF % (attendu 6000)', round(ir), round(tr); end if;
end $$;
select 'OK moteur_reference_2026';
