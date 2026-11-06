-- Lot C : barème de la quotité cessible et vue de contrôle (lecture seule, aucune donnée écrite)
do $$
begin
  assert public.quotite_cessible(50000)  = 10000,  'quotité 50 000';
  assert public.quotite_cessible(150000) = 45000,  'quotité 150 000';
  assert public.quotite_cessible(300000) = 165000, 'quotité 300 000';
  assert not exists (select 1 from public.v_conformite_retenues
                      where not (depasse_quotite_cessible or depasse_plafond_global)), 'vue : ligne sans dépassement';
  raise notice 'lotc_controle_retenues : OK';
end $$;
