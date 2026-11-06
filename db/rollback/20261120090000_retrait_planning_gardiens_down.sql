-- Retour du retrait du planning des postes : recrée la structure (tables, index, politiques, déclencheurs, droits) et la fonction.
-- Les DONNÉES ne reviennent que par la sauvegarde `backups/soma_rh_avant_retrait_gardiens_<horodatage>_donnees.sql` (COPY seul), à charger après ce fichier.
--
-- PostgreSQL database dump
--


-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11




--
-- Name: shift_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_assignments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    work_date date NOT NULL,
    shift_code text NOT NULL,
    post_id uuid,
    notes text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: shift_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_types (
    code text NOT NULL,
    label text NOT NULL,
    start_time time without time zone,
    end_time time without time zone,
    hours numeric DEFAULT 0 NOT NULL,
    is_night boolean DEFAULT false NOT NULL,
    is_rest boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 100 NOT NULL,
    CONSTRAINT shift_types_hours_check CHECK (((hours >= (0)::numeric) AND (hours <= (24)::numeric)))
);


--
-- Name: work_posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    site text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT work_posts_name_check CHECK ((length(TRIM(BOTH FROM name)) > 0))
);


--
-- Name: shift_assignments shift_assignments_employee_id_work_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_employee_id_work_date_key UNIQUE (employee_id, work_date);


--
-- Name: shift_assignments shift_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_pkey PRIMARY KEY (id);


--
-- Name: shift_types shift_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_types
    ADD CONSTRAINT shift_types_pkey PRIMARY KEY (code);


--
-- Name: work_posts work_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_posts
    ADD CONSTRAINT work_posts_pkey PRIMARY KEY (id);


--
-- Name: shift_assignments_code_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shift_assignments_code_idx ON public.shift_assignments USING btree (shift_code);


--
-- Name: shift_assignments_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shift_assignments_date_idx ON public.shift_assignments USING btree (work_date);


--
-- Name: shift_assignments_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shift_assignments_employee_idx ON public.shift_assignments USING btree (employee_id);


--
-- Name: shift_assignments_post_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shift_assignments_post_idx ON public.shift_assignments USING btree (post_id);


--
-- Name: work_posts_name_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX work_posts_name_uq ON public.work_posts USING btree (lower(TRIM(BOTH FROM name)));


--
-- Name: shift_types shift_types_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER shift_types_audit AFTER INSERT OR DELETE OR UPDATE ON public.shift_types FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: work_posts work_posts_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER work_posts_audit AFTER INSERT OR DELETE OR UPDATE ON public.work_posts FOR EACH ROW EXECUTE FUNCTION public.business_audit();


--
-- Name: shift_assignments shift_assignments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: shift_assignments shift_assignments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: shift_assignments shift_assignments_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.work_posts(id) ON DELETE SET NULL;


--
-- Name: shift_assignments shift_assignments_shift_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_assignments
    ADD CONSTRAINT shift_assignments_shift_code_fkey FOREIGN KEY (shift_code) REFERENCES public.shift_types(code);


--
-- Name: shift_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: shift_assignments shift_assignments_access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shift_assignments_access ON public.shift_assignments TO authenticated USING ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (employee_id = ( SELECT public.my_employee_id() AS my_employee_id)))) WITH CHECK ((( SELECT public.has_role(ARRAY['rh'::text]) AS has_role) OR (employee_id = ( SELECT public.my_employee_id() AS my_employee_id))));


--
-- Name: shift_types; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_types ENABLE ROW LEVEL SECURITY;

--
-- Name: shift_types shift_types_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shift_types_admin ON public.shift_types TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text, 'paie'::text]) AS has_role));


--
-- Name: shift_types shift_types_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shift_types_read ON public.shift_types FOR SELECT TO authenticated USING (true);


--
-- Name: work_posts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_posts ENABLE ROW LEVEL SECURITY;

--
-- Name: work_posts work_posts_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_posts_admin ON public.work_posts TO authenticated USING (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role)) WITH CHECK (( SELECT public.has_role(ARRAY['rh'::text]) AS has_role));


--
-- Name: work_posts work_posts_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY work_posts_read ON public.work_posts FOR SELECT TO authenticated USING (true);


--
-- Name: TABLE shift_assignments; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.shift_assignments TO authenticated;


--
-- Name: TABLE shift_types; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.shift_types TO authenticated;


--
-- Name: TABLE work_posts; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.work_posts TO authenticated;


--
-- PostgreSQL database dump complete
--



CREATE OR REPLACE FUNCTION public.generate_rotation(p_employee_ids uuid[], p_from date, p_to date, p_pattern text[], p_offset integer DEFAULT 0, p_post_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_n integer;
begin
  if not public.has_role(array['rh']) then
    raise exception 'Droits insuffisants : rôle « rh » requis';
  end if;
  if p_to < p_from or p_to - p_from > 366 then
    raise exception 'Période invalide (366 jours maximum)';
  end if;
  if coalesce(array_length(p_pattern, 1), 0) = 0 then
    raise exception 'Cycle vide';
  end if;
  if exists (
    select 1 from unnest(p_pattern) c
    where not exists (select 1 from public.shift_types t where t.code = c)
  ) then
    raise exception 'Cycle : code de poste inconnu';
  end if;
  insert into public.shift_assignments (employee_id, work_date, shift_code, post_id)
  select e, d::date,
    p_pattern[1 + (((d::date - p_from) + p_offset) % array_length(p_pattern, 1) + array_length(p_pattern, 1)) % array_length(p_pattern, 1)],
    p_post_id
  from unnest(p_employee_ids) e, generate_series(p_from, p_to, interval '1 day') d
  on conflict (employee_id, work_date) do update
    set shift_code = excluded.shift_code, post_id = excluded.post_id;
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;
notify pgrst, 'reload schema';
