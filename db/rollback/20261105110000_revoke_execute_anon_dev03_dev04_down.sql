-- Retour de D-014 : rend l'exécution à PUBLIC pour les 5 fonctions concernées.
grant execute on function public.export_payroll_journal(uuid), public.validate_journal_balance(uuid),
  public.check_journal_imputation(uuid), public.export_ipres_css(uuid, date), public.etat_dgid(uuid, date, text) to public;
