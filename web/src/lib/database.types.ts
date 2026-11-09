export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  __InternalSupabase: {
    PostgrestVersion: "14.17"
  }
  public: {
    Tables: {
      additional_salaries: {
        Row: {
          amount: number
          component_code: string
          created_at: string
          employee_id: string
          id: string
          kind: string
          notes: string | null
          period: string
          source_id: string | null
        }
        ComputedFields: never
        Insert: {
          amount: number
          component_code: string
          created_at?: string
          employee_id: string
          id?: string
          kind?: string
          notes?: string | null
          period: string
          source_id?: string | null
        }
        Update: {
          amount?: number
          component_code?: string
          created_at?: string
          employee_id?: string
          id?: string
          kind?: string
          notes?: string | null
          period?: string
          source_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "additional_salaries_component_code_fkey"
            columns: ["component_code"]
            isOneToOne: false
            referencedRelation: "salary_components"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "additional_salaries_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "additional_salaries_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "additional_salaries_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      app_parameters: {
        Row: {
          code: string
          label: string
          updated_at: string
          updated_by: string | null
          value: number
        }
        ComputedFields: never
        Insert: {
          code: string
          label: string
          updated_at?: string
          updated_by?: string | null
          value: number
        }
        Update: {
          code?: string
          label?: string
          updated_at?: string
          updated_by?: string | null
          value?: number
        }
        Relationships: []
      }
      approval_delegations: {
        Row: {
          active: boolean
          created_at: string
          delegate_user: string
          delegator_user: string
          id: string
          reason: string | null
          valid_from: string
          valid_to: string
        }
        ComputedFields: never
        Insert: {
          active?: boolean
          created_at?: string
          delegate_user: string
          delegator_user: string
          id?: string
          reason?: string | null
          valid_from: string
          valid_to: string
        }
        Update: {
          active?: boolean
          created_at?: string
          delegate_user?: string
          delegator_user?: string
          id?: string
          reason?: string | null
          valid_from?: string
          valid_to?: string
        }
        Relationships: []
      }
      approval_requests: {
        Row: {
          decided_at: string | null
          decided_by: string | null
          decision_note: string | null
          id: string
          kind: string
          payload: NonNullable<Json>
          requested_at: string
          requested_by: string | null
          status: string
          summary: string
          target: string
        }
        ComputedFields: never
        Insert: {
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          id?: string
          kind: string
          payload: NonNullable<Json>
          requested_at?: string
          requested_by?: string | null
          status?: string
          summary: string
          target: string
        }
        Update: {
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          id?: string
          kind?: string
          payload?: NonNullable<Json>
          requested_at?: string
          requested_by?: string | null
          status?: string
          summary?: string
          target?: string
        }
        Relationships: []
      }
      attendance: {
        Row: {
          absence_hours: number
          attendance_date: string
          created_at: string
          employee_id: string
          id: string
          leave_application_id: string | null
          notes: string | null
          overtime_100: number
          overtime_15: number
          overtime_40: number
          overtime_60: number
          sick_hours: number
          status: string
          updated_at: string
          updated_by: string | null
          working_hours: number | null
        }
        ComputedFields: never
        Insert: {
          absence_hours?: number
          attendance_date: string
          created_at?: string
          employee_id: string
          id?: string
          leave_application_id?: string | null
          notes?: string | null
          overtime_100?: number
          overtime_15?: number
          overtime_40?: number
          overtime_60?: number
          sick_hours?: number
          status: string
          updated_at?: string
          updated_by?: string | null
          working_hours?: number | null
        }
        Update: {
          absence_hours?: number
          attendance_date?: string
          created_at?: string
          employee_id?: string
          id?: string
          leave_application_id?: string | null
          notes?: string | null
          overtime_100?: number
          overtime_15?: number
          overtime_40?: number
          overtime_60?: number
          sick_hours?: number
          status?: string
          updated_at?: string
          updated_by?: string | null
          working_hours?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "attendance_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "attendance_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "attendance_leave_application_id_fkey"
            columns: ["leave_application_id"]
            isOneToOne: false
            referencedRelation: "leave_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_events: {
        Row: {
          action: string
          actor_id: string | null
          after_data: Json | null
          before_data: Json | null
          created_at: string
          id: string
          payroll_entry_id: string | null
          reason: string | null
          resource_id: string | null
          resource_type: string
          result: string
        }
        ComputedFields: never
        Insert: {
          action: string
          actor_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          created_at?: string
          id?: string
          payroll_entry_id?: string | null
          reason?: string | null
          resource_id?: string | null
          resource_type: string
          result?: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          after_data?: Json | null
          before_data?: Json | null
          created_at?: string
          id?: string
          payroll_entry_id?: string | null
          reason?: string | null
          resource_id?: string | null
          resource_type?: string
          result?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_events_payroll_entry_id_fkey"
            columns: ["payroll_entry_id"]
            isOneToOne: false
            referencedRelation: "payroll_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_log: {
        Row: {
          action: string
          actor: string | null
          chain_pos: number | null
          id: number
          new_data: Json | null
          occurred_at: string
          old_data: Json | null
          payroll_entry_id: string | null
          prev_hash: string | null
          reason: string | null
          record_id: string | null
          record_key: string | null
          result: string
          row_hash: string | null
          source_event_id: string | null
          table_name: string
        }
        ComputedFields: never
        Insert: {
          action: string
          actor?: string | null
          chain_pos?: number | null
          id?: never
          new_data?: Json | null
          occurred_at?: string
          old_data?: Json | null
          payroll_entry_id?: string | null
          prev_hash?: string | null
          reason?: string | null
          record_id?: string | null
          record_key?: string | null
          result?: string
          row_hash?: string | null
          source_event_id?: string | null
          table_name: string
        }
        Update: {
          action?: string
          actor?: string | null
          chain_pos?: number | null
          id?: never
          new_data?: Json | null
          occurred_at?: string
          old_data?: Json | null
          payroll_entry_id?: string | null
          prev_hash?: string | null
          reason?: string | null
          record_id?: string | null
          record_key?: string | null
          result?: string
          row_hash?: string | null
          source_event_id?: string | null
          table_name?: string
        }
        Relationships: []
      }
      candidatures: {
        Row: {
          created_at: string
          created_by: string | null
          employee_id: string
          id: string
          job_postulation_id: string
          motivation: string | null
          status: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          created_by?: string | null
          employee_id: string
          id?: string
          job_postulation_id: string
          motivation?: string | null
          status?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          employee_id?: string
          id?: string
          job_postulation_id?: string
          motivation?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "candidatures_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidatures_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "candidatures_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "candidatures_job_postulation_id_fkey"
            columns: ["job_postulation_id"]
            isOneToOne: false
            referencedRelation: "job_postulations"
            referencedColumns: ["id"]
          },
        ]
      }
      collective_agreements: {
        Row: {
          code: string
          created_at: string
          is_active: boolean
          name: string
          updated_at: string
          updated_by: string | null
        }
        ComputedFields: never
        Insert: {
          code: string
          created_at?: string
          is_active?: boolean
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          is_active?: boolean
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      companies: {
        Row: {
          address: string | null
          collective_agreement_code: string | null
          created_at: string
          css_at_rate: number | null
          css_number: string | null
          currency: string
          email: string | null
          ett_agreement_number: string | null
          id: string
          ipres_number: string | null
          is_ett: boolean
          legal_form: string | null
          logo_url: string | null
          name: string
          ninea: string | null
          phone: string | null
          rccm: string | null
          share_capital: number | null
          social_regularity_cert_date: string | null
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          address?: string | null
          collective_agreement_code?: string | null
          created_at?: string
          css_at_rate?: number | null
          css_number?: string | null
          currency?: string
          email?: string | null
          ett_agreement_number?: string | null
          id?: string
          ipres_number?: string | null
          is_ett?: boolean
          legal_form?: string | null
          logo_url?: string | null
          name: string
          ninea?: string | null
          phone?: string | null
          rccm?: string | null
          share_capital?: number | null
          social_regularity_cert_date?: string | null
          updated_at?: string
        }
        Update: {
          address?: string | null
          collective_agreement_code?: string | null
          created_at?: string
          css_at_rate?: number | null
          css_number?: string | null
          currency?: string
          email?: string | null
          ett_agreement_number?: string | null
          id?: string
          ipres_number?: string | null
          is_ett?: boolean
          legal_form?: string | null
          logo_url?: string | null
          name?: string
          ninea?: string | null
          phone?: string | null
          rccm?: string | null
          share_capital?: number | null
          social_regularity_cert_date?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "companies_collective_agreement_code_fkey"
            columns: ["collective_agreement_code"]
            isOneToOne: false
            referencedRelation: "collective_agreements"
            referencedColumns: ["code"]
          },
        ]
      }
      compliance_findings: {
        Row: {
          created_at: string
          detected_on: string
          employee_id: string | null
          entity: string
          entity_id: string | null
          id: string
          message: string
          resolved_on: string | null
          rule_id: string
          severity: string
          waived_by: string | null
          waiver_reason: string | null
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          detected_on?: string
          employee_id?: string | null
          entity: string
          entity_id?: string | null
          id?: string
          message: string
          resolved_on?: string | null
          rule_id: string
          severity: string
          waived_by?: string | null
          waiver_reason?: string | null
        }
        Update: {
          created_at?: string
          detected_on?: string
          employee_id?: string | null
          entity?: string
          entity_id?: string | null
          id?: string
          message?: string
          resolved_on?: string | null
          rule_id?: string
          severity?: string
          waived_by?: string | null
          waiver_reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "compliance_findings_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compliance_findings_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "compliance_findings_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      compliance_rules: {
        Row: {
          domain: string
          fix_target: string
          label: string
          legal_ref: string | null
          rule_id: string
          suggested_action: string
        }
        ComputedFields: never
        Insert: {
          domain: string
          fix_target?: string
          label: string
          legal_ref?: string | null
          rule_id: string
          suggested_action: string
        }
        Update: {
          domain?: string
          fix_target?: string
          label?: string
          legal_ref?: string | null
          rule_id?: string
          suggested_action?: string
        }
        Relationships: []
      }
      compliance_scans: {
        Row: {
          id: string
          nb_alertes: number
          nb_bloquants: number
          nb_derogations: number
          nb_salaries: number
          scanned_at: string
          scanned_by: string | null
          status: string
          summary: NonNullable<Json>
        }
        ComputedFields: never
        Insert: {
          id?: string
          nb_alertes: number
          nb_bloquants: number
          nb_derogations: number
          nb_salaries: number
          scanned_at?: string
          scanned_by?: string | null
          status: string
          summary?: NonNullable<Json>
        }
        Update: {
          id?: string
          nb_alertes?: number
          nb_bloquants?: number
          nb_derogations?: number
          nb_salaries?: number
          scanned_at?: string
          scanned_by?: string | null
          status?: string
          summary?: NonNullable<Json>
        }
        Relationships: []
      }
      compliance_waivers: {
        Row: {
          employee_id: string | null
          ended_at: string | null
          ended_by: string | null
          ended_reason: string | null
          entity_id: string
          granted_at: string
          granted_by: string | null
          id: string
          parameter_code: string | null
          parameter_value: number | null
          reason: string
          requested_by: string | null
          rule_id: string
          status: string
        }
        ComputedFields: never
        Insert: {
          employee_id?: string | null
          ended_at?: string | null
          ended_by?: string | null
          ended_reason?: string | null
          entity_id: string
          granted_at?: string
          granted_by?: string | null
          id?: string
          parameter_code?: string | null
          parameter_value?: number | null
          reason: string
          requested_by?: string | null
          rule_id: string
          status?: string
        }
        Update: {
          employee_id?: string | null
          ended_at?: string | null
          ended_by?: string | null
          ended_reason?: string | null
          entity_id?: string
          granted_at?: string
          granted_by?: string | null
          id?: string
          parameter_code?: string | null
          parameter_value?: number | null
          reason?: string
          requested_by?: string | null
          rule_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "compliance_waivers_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "compliance_waivers_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "compliance_waivers_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      contract_types: {
        Row: {
          code: string
          created_at: string
          is_active: boolean
          label: string
          nature: string
          precarity_eligible: boolean
          severance_eligible: boolean
          sort_order: number
          updated_at: string
          updated_by: string | null
        }
        ComputedFields: never
        Insert: {
          code: string
          created_at?: string
          is_active?: boolean
          label: string
          nature?: string
          precarity_eligible?: boolean
          severance_eligible?: boolean
          sort_order?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          is_active?: boolean
          label?: string
          nature?: string
          precarity_eligible?: boolean
          severance_eligible?: boolean
          sort_order?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      contribution_payments: {
        Row: {
          amount: number
          created_at: string
          created_by: string | null
          month: string
          notes: string | null
          paid_on: string
        }
        ComputedFields: never
        Insert: {
          amount: number
          created_at?: string
          created_by?: string | null
          month: string
          notes?: string | null
          paid_on: string
        }
        Update: {
          amount?: number
          created_at?: string
          created_by?: string | null
          month?: string
          notes?: string | null
          paid_on?: string
        }
        Relationships: []
      }
      delegate_seats: {
        Row: {
          id: string
          seats: number
          source_code: string | null
          workers_max: number | null
          workers_min: number
        }
        ComputedFields: never
        Insert: {
          id?: string
          seats: number
          source_code?: string | null
          workers_max?: number | null
          workers_min: number
        }
        Update: {
          id?: string
          seats?: number
          source_code?: string | null
          workers_max?: number | null
          workers_min?: number
        }
        Relationships: [
          {
            foreignKeyName: "delegate_seats_source_code_fkey"
            columns: ["source_code"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["code"]
          },
        ]
      }
      departments: {
        Row: {
          company_id: string
          created_at: string
          head_employee_id: string | null
          id: string
          kind: string
          name: string
          note: string | null
          parent_id: string | null
        }
        ComputedFields: never
        Insert: {
          company_id: string
          created_at?: string
          head_employee_id?: string | null
          id?: string
          kind?: string
          name: string
          note?: string | null
          parent_id?: string | null
        }
        Update: {
          company_id?: string
          created_at?: string
          head_employee_id?: string | null
          id?: string
          kind?: string
          name?: string
          note?: string | null
          parent_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "departments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "departments_head_employee_id_fkey"
            columns: ["head_employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "departments_head_employee_id_fkey"
            columns: ["head_employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "departments_head_employee_id_fkey"
            columns: ["head_employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "departments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
        ]
      }
      designations: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          name: string
          updated_at: string
          updated_by: string | null
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      document_requirements: {
        Row: {
          active: boolean
          allowed_mime_types: string[]
          code: string
          conditional_rule: string | null
          created_at: string
          description: string
          icon: string | null
          manager_shareable: boolean
          max_size_bytes: number
          required: boolean
          section_code: string
          sort_order: number
          title: string
          validity_days: number | null
        }
        ComputedFields: never
        Insert: {
          active?: boolean
          allowed_mime_types?: string[]
          code: string
          conditional_rule?: string | null
          created_at?: string
          description: string
          icon?: string | null
          manager_shareable?: boolean
          max_size_bytes?: number
          required?: boolean
          section_code: string
          sort_order?: number
          title: string
          validity_days?: number | null
        }
        Update: {
          active?: boolean
          allowed_mime_types?: string[]
          code?: string
          conditional_rule?: string | null
          created_at?: string
          description?: string
          icon?: string | null
          manager_shareable?: boolean
          max_size_bytes?: number
          required?: boolean
          section_code?: string
          sort_order?: number
          title?: string
          validity_days?: number | null
        }
        Relationships: []
      }
      document_reviews: {
        Row: {
          document_id: string
          id: string
          reason: string | null
          reviewed_at: string
          reviewed_by: string
          status: string
        }
        ComputedFields: never
        Insert: {
          document_id: string
          id?: string
          reason?: string | null
          reviewed_at?: string
          reviewed_by?: string
          status: string
        }
        Update: {
          document_id?: string
          id?: string
          reason?: string | null
          reviewed_at?: string
          reviewed_by?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_reviews_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "employee_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      document_templates: {
        Row: {
          body: string
          code: string
          title: string
          updated_at: string
          updated_by: string | null
          version: number
        }
        ComputedFields: never
        Insert: {
          body: string
          code: string
          title: string
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Update: {
          body?: string
          code?: string
          title?: string
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Relationships: []
      }
      document_versions: {
        Row: {
          checksum: string | null
          document_id: string
          file_name: string
          id: string
          mime_type: string
          size_bytes: number
          storage_path: string
          uploaded_at: string
          uploaded_by: string
          version_number: number
        }
        ComputedFields: never
        Insert: {
          checksum?: string | null
          document_id: string
          file_name: string
          id?: string
          mime_type: string
          size_bytes: number
          storage_path: string
          uploaded_at?: string
          uploaded_by?: string
          version_number: number
        }
        Update: {
          checksum?: string | null
          document_id?: string
          file_name?: string
          id?: string
          mime_type?: string
          size_bytes?: number
          storage_path?: string
          uploaded_at?: string
          uploaded_by?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "document_versions_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "employee_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      email_outbox: {
        Row: {
          attempts: number
          body: string
          created_at: string
          dedup_key: string
          id: string
          last_error: string | null
          sent_at: string | null
          status: string
          subject: string
          to_email: string
        }
        ComputedFields: never
        Insert: {
          attempts?: number
          body: string
          created_at?: string
          dedup_key: string
          id?: string
          last_error?: string | null
          sent_at?: string | null
          status?: string
          subject: string
          to_email: string
        }
        Update: {
          attempts?: number
          body?: string
          created_at?: string
          dedup_key?: string
          id?: string
          last_error?: string | null
          sent_at?: string | null
          status?: string
          subject?: string
          to_email?: string
        }
        Relationships: []
      }
      employee_document_access_log: {
        Row: {
          accessed_at: string
          document_id: string
          id: string
          user_id: string
        }
        ComputedFields: never
        Insert: {
          accessed_at?: string
          document_id: string
          id?: string
          user_id?: string
        }
        Update: {
          accessed_at?: string
          document_id?: string
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_document_access_log_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "employee_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_documents: {
        Row: {
          archived_at: string | null
          archived_by: string | null
          checksum: string | null
          created_at: string
          created_by: string
          current_version: number
          document_slot: number
          document_type: string
          employee_id: string
          file_name: string
          id: string
          mime_type: string
          rejection_reason: string | null
          requirement_code: string | null
          size_bytes: number
          status: string
          storage_path: string
          submitted_at: string | null
          thumbnail_path: string | null
          title: string
          validated_at: string | null
          validated_by: string | null
        }
        ComputedFields: never
        Insert: {
          archived_at?: string | null
          archived_by?: string | null
          checksum?: string | null
          created_at?: string
          created_by?: string
          current_version?: number
          document_slot?: number
          document_type: string
          employee_id: string
          file_name: string
          id?: string
          mime_type: string
          rejection_reason?: string | null
          requirement_code?: string | null
          size_bytes: number
          status?: string
          storage_path: string
          submitted_at?: string | null
          thumbnail_path?: string | null
          title: string
          validated_at?: string | null
          validated_by?: string | null
        }
        Update: {
          archived_at?: string | null
          archived_by?: string | null
          checksum?: string | null
          created_at?: string
          created_by?: string
          current_version?: number
          document_slot?: number
          document_type?: string
          employee_id?: string
          file_name?: string
          id?: string
          mime_type?: string
          rejection_reason?: string | null
          requirement_code?: string | null
          size_bytes?: number
          status?: string
          storage_path?: string
          submitted_at?: string | null
          thumbnail_path?: string | null
          title?: string
          validated_at?: string | null
          validated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employee_documents_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_documents_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_documents_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_documents_requirement_code_fkey"
            columns: ["requirement_code"]
            isOneToOne: false
            referencedRelation: "document_requirements"
            referencedColumns: ["code"]
          },
        ]
      }
      employee_grades: {
        Row: {
          agreement_code: string
          base_salary: number
          code: string
          created_at: string
          effective_from: string
          grade_class: string | null
          hourly_rate: number
          id: string
          is_active: boolean
          staff_status: string
          updated_at: string
          updated_by: string | null
        }
        ComputedFields: never
        Insert: {
          agreement_code: string
          base_salary: number
          code: string
          created_at?: string
          effective_from?: string
          grade_class?: string | null
          hourly_rate: number
          id?: string
          is_active?: boolean
          staff_status: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          agreement_code?: string
          base_salary?: number
          code?: string
          created_at?: string
          effective_from?: string
          grade_class?: string | null
          hourly_rate?: number
          id?: string
          is_active?: boolean
          staff_status?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employee_grades_agreement_code_fkey"
            columns: ["agreement_code"]
            isOneToOne: false
            referencedRelation: "collective_agreements"
            referencedColumns: ["code"]
          },
        ]
      }
      employee_manager_assignments: {
        Row: {
          created_at: string
          delegated_by: string
          employee_id: string
          id: string
          manager_employee_id: string
          valid_from: string
          valid_to: string | null
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          delegated_by?: string
          employee_id: string
          id?: string
          manager_employee_id: string
          valid_from: string
          valid_to?: string | null
        }
        Update: {
          created_at?: string
          delegated_by?: string
          employee_id?: string
          id?: string
          manager_employee_id?: string
          valid_from?: string
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employee_manager_assignments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_manager_assignments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_manager_assignments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_manager_assignments_manager_employee_id_fkey"
            columns: ["manager_employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_manager_assignments_manager_employee_id_fkey"
            columns: ["manager_employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_manager_assignments_manager_employee_id_fkey"
            columns: ["manager_employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      employee_module_data: {
        Row: {
          data: NonNullable<Json>
          employee_id: string
          id: string
          module_id: string
          valid_from: string | null
          valid_to: string | null
        }
        ComputedFields: never
        Insert: {
          data?: NonNullable<Json>
          employee_id: string
          id?: string
          module_id: string
          valid_from?: string | null
          valid_to?: string | null
        }
        Update: {
          data?: NonNullable<Json>
          employee_id?: string
          id?: string
          module_id?: string
          valid_from?: string | null
          valid_to?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employee_module_data_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_module_data_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_module_data_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_module_data_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "module_manifest"
            referencedColumns: ["module_id"]
          },
        ]
      }
      employee_notifications: {
        Row: {
          created_at: string
          id: string
          message: string
          read_at: string | null
          request_id: string | null
          title: string
          user_id: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          id?: string
          message: string
          read_at?: string | null
          request_id?: string | null
          title: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          message?: string
          read_at?: string | null
          request_id?: string | null
          title?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_notifications_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "employee_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_representatives: {
        Row: {
          created_at: string
          employee_id: string
          end_date: string | null
          id: string
          mandate: string
          start_date: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          employee_id: string
          end_date?: string | null
          id?: string
          mandate: string
          start_date: string
        }
        Update: {
          created_at?: string
          employee_id?: string
          end_date?: string | null
          id?: string
          mandate?: string
          start_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_representatives_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_representatives_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_representatives_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      employee_request_history: {
        Row: {
          actor_id: string
          created_at: string
          id: string
          note: string | null
          request_id: string
          status: string
        }
        ComputedFields: never
        Insert: {
          actor_id?: string
          created_at?: string
          id?: string
          note?: string | null
          request_id: string
          status: string
        }
        Update: {
          actor_id?: string
          created_at?: string
          id?: string
          note?: string | null
          request_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "employee_request_history_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "employee_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      employee_requests: {
        Row: {
          amount: number | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_note: string | null
          employee_id: string
          id: string
          message: string | null
          request_type: string
          status: string
          target_date: string | null
        }
        ComputedFields: never
        Insert: {
          amount?: number | null
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          employee_id: string
          id?: string
          message?: string | null
          request_type: string
          status?: string
          target_date?: string | null
        }
        Update: {
          amount?: number | null
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          decision_note?: string | null
          employee_id?: string
          id?: string
          message?: string | null
          request_type?: string
          status?: string
          target_date?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employee_requests_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employee_requests_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "employee_requests_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      employees: {
        Row: {
          address: string | null
          affiliation_date: string | null
          agreement_code: string | null
          bank_account: string | null
          bank_name: string | null
          children_count: number
          company_id: string
          contract_end: string | null
          contract_start: string | null
          created_at: string
          css_number: string | null
          date_of_birth: string | null
          date_of_joining: string
          department_id: string | null
          designation_id: string | null
          email_personal: string | null
          email_work: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          employee_number: string
          employment_type: string
          exit_reason: string | null
          father_name: string | null
          first_name: string
          gender: string | null
          grade_id: string | null
          hire_declaration_ref: string | null
          hire_declared_on: string | null
          id: string
          id_document_number: string | null
          id_expiry_date: string | null
          id_issue_date: string | null
          ipres_number: string | null
          ir_parts: number
          last_name: string
          leave_return_date: string | null
          marital_status: string | null
          mother_name: string | null
          nationality: string | null
          ninea: string | null
          payment_mode: string
          phone_personal: string | null
          phone_work: string | null
          place_of_birth: string | null
          relieving_date: string | null
          spouses_count: number
          status: string
          trimf_parts: number
          updated_at: string
          user_id: string | null
        }
        ComputedFields: never
        Insert: {
          address?: string | null
          affiliation_date?: string | null
          agreement_code?: string | null
          bank_account?: string | null
          bank_name?: string | null
          children_count?: number
          company_id: string
          contract_end?: string | null
          contract_start?: string | null
          created_at?: string
          css_number?: string | null
          date_of_birth?: string | null
          date_of_joining: string
          department_id?: string | null
          designation_id?: string | null
          email_personal?: string | null
          email_work?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          employee_number: string
          employment_type: string
          exit_reason?: string | null
          father_name?: string | null
          first_name: string
          gender?: string | null
          grade_id?: string | null
          hire_declaration_ref?: string | null
          hire_declared_on?: string | null
          id?: string
          id_document_number?: string | null
          id_expiry_date?: string | null
          id_issue_date?: string | null
          ipres_number?: string | null
          ir_parts?: number
          last_name: string
          leave_return_date?: string | null
          marital_status?: string | null
          mother_name?: string | null
          nationality?: string | null
          ninea?: string | null
          payment_mode?: string
          phone_personal?: string | null
          phone_work?: string | null
          place_of_birth?: string | null
          relieving_date?: string | null
          spouses_count?: number
          status?: string
          trimf_parts?: number
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          address?: string | null
          affiliation_date?: string | null
          agreement_code?: string | null
          bank_account?: string | null
          bank_name?: string | null
          children_count?: number
          company_id?: string
          contract_end?: string | null
          contract_start?: string | null
          created_at?: string
          css_number?: string | null
          date_of_birth?: string | null
          date_of_joining?: string
          department_id?: string | null
          designation_id?: string | null
          email_personal?: string | null
          email_work?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          employee_number?: string
          employment_type?: string
          exit_reason?: string | null
          father_name?: string | null
          first_name?: string
          gender?: string | null
          grade_id?: string | null
          hire_declaration_ref?: string | null
          hire_declared_on?: string | null
          id?: string
          id_document_number?: string | null
          id_expiry_date?: string | null
          id_issue_date?: string | null
          ipres_number?: string | null
          ir_parts?: number
          last_name?: string
          leave_return_date?: string | null
          marital_status?: string | null
          mother_name?: string | null
          nationality?: string | null
          ninea?: string | null
          payment_mode?: string
          phone_personal?: string | null
          phone_work?: string | null
          place_of_birth?: string | null
          relieving_date?: string | null
          spouses_count?: number
          status?: string
          trimf_parts?: number
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "employees_agreement_code_fkey"
            columns: ["agreement_code"]
            isOneToOne: false
            referencedRelation: "collective_agreements"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "employees_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_department_id_fkey"
            columns: ["department_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_designation_id_fkey"
            columns: ["designation_id"]
            isOneToOne: false
            referencedRelation: "designations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_employment_type_fkey"
            columns: ["employment_type"]
            isOneToOne: false
            referencedRelation: "contract_types"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "employees_exit_reason_fk"
            columns: ["exit_reason"]
            isOneToOne: false
            referencedRelation: "exit_reasons"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "employees_grade_id_fkey"
            columns: ["grade_id"]
            isOneToOne: false
            referencedRelation: "employee_grades"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "employees_payment_mode_fkey"
            columns: ["payment_mode"]
            isOneToOne: false
            referencedRelation: "payment_modes"
            referencedColumns: ["code"]
          },
        ]
      }
      evaluations: {
        Row: {
          commentaires: string | null
          created_at: string
          employee_id: string
          evaluator: string | null
          global_note: number | null
          id: string
          period: string | null
          updated_at: string | null
        }
        ComputedFields: never
        Insert: {
          commentaires?: string | null
          created_at?: string
          employee_id: string
          evaluator?: string | null
          global_note?: number | null
          id?: string
          period?: string | null
          updated_at?: string | null
        }
        Update: {
          commentaires?: string | null
          created_at?: string
          employee_id?: string
          evaluator?: string | null
          global_note?: number | null
          id?: string
          period?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "evaluations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "evaluations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "evaluations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      exit_reasons: {
        Row: {
          code: string
          funeral_indemnity_months: number
          is_legacy: boolean
          label: string
          notes: string | null
          retirement_indemnity: boolean
          severance_eligible: boolean
          sort_order: number
          source_code: string | null
          special_indemnity_months: number
        }
        ComputedFields: never
        Insert: {
          code: string
          funeral_indemnity_months?: number
          is_legacy?: boolean
          label: string
          notes?: string | null
          retirement_indemnity?: boolean
          severance_eligible?: boolean
          sort_order?: number
          source_code?: string | null
          special_indemnity_months?: number
        }
        Update: {
          code?: string
          funeral_indemnity_months?: number
          is_legacy?: boolean
          label?: string
          notes?: string | null
          retirement_indemnity?: boolean
          severance_eligible?: boolean
          sort_order?: number
          source_code?: string | null
          special_indemnity_months?: number
        }
        Relationships: [
          {
            foreignKeyName: "exit_reasons_source_code_fkey"
            columns: ["source_code"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["code"]
          },
        ]
      }
      garnishment_scale: {
        Row: {
          effective_from: string
          id: string
          kind: string
          lower_bound: number
          rate: number
          source_code: string | null
          upper_bound: number | null
        }
        ComputedFields: never
        Insert: {
          effective_from?: string
          id?: string
          kind: string
          lower_bound: number
          rate: number
          source_code?: string | null
          upper_bound?: number | null
        }
        Update: {
          effective_from?: string
          id?: string
          kind?: string
          lower_bound?: number
          rate?: number
          source_code?: string | null
          upper_bound?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "garnishment_scale_source_code_fkey"
            columns: ["source_code"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["code"]
          },
        ]
      }
      ir_family_reductions: {
        Row: {
          id: string
          max_amount: number
          min_amount: number
          parts: number
          rate: number
          slab_id: string
        }
        ComputedFields: never
        Insert: {
          id?: string
          max_amount: number
          min_amount: number
          parts: number
          rate: number
          slab_id: string
        }
        Update: {
          id?: string
          max_amount?: number
          min_amount?: number
          parts?: number
          rate?: number
          slab_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ir_family_reductions_slab_id_fkey"
            columns: ["slab_id"]
            isOneToOne: false
            referencedRelation: "tax_slabs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_postulations: {
        Row: {
          created_at: string
          created_by: string | null
          department: string | null
          employee_id: string
          id: string
          job_title: string
          source: string | null
          source_id: string | null
          status: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          created_by?: string | null
          department?: string | null
          employee_id: string
          id?: string
          job_title: string
          source?: string | null
          source_id?: string | null
          status?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          department?: string | null
          employee_id?: string
          id?: string
          job_title?: string
          source?: string | null
          source_id?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_postulations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_postulations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "job_postulations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      leave_allocations: {
        Row: {
          created_at: string
          days: number
          employee_id: string
          from_date: string
          id: string
          leave_type: string
          notes: string | null
          to_date: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          days: number
          employee_id: string
          from_date: string
          id?: string
          leave_type: string
          notes?: string | null
          to_date: string
        }
        Update: {
          created_at?: string
          days?: number
          employee_id?: string
          from_date?: string
          id?: string
          leave_type?: string
          notes?: string | null
          to_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "leave_allocations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_allocations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "leave_allocations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "leave_allocations_leave_type_fkey"
            columns: ["leave_type"]
            isOneToOne: false
            referencedRelation: "leave_types"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "leave_allocations_leave_type_fkey"
            columns: ["leave_type"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["leave_type"]
          },
        ]
      }
      leave_applications: {
        Row: {
          approved_at: string | null
          approver_id: string | null
          created_at: string
          created_by: string | null
          employee_id: string
          from_date: string
          half_day: boolean
          id: string
          leave_type: string
          reason: string | null
          status: string
          to_date: string
          total_days: number | null
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          approved_at?: string | null
          approver_id?: string | null
          created_at?: string
          created_by?: string | null
          employee_id: string
          from_date: string
          half_day?: boolean
          id?: string
          leave_type: string
          reason?: string | null
          status?: string
          to_date: string
          total_days?: never
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approver_id?: string | null
          created_at?: string
          created_by?: string | null
          employee_id?: string
          from_date?: string
          half_day?: boolean
          id?: string
          leave_type?: string
          reason?: string | null
          status?: string
          to_date?: string
          total_days?: never
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "leave_applications_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_applications_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "leave_applications_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "leave_applications_leave_type_fkey"
            columns: ["leave_type"]
            isOneToOne: false
            referencedRelation: "leave_types"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "leave_applications_leave_type_fkey"
            columns: ["leave_type"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["leave_type"]
          },
        ]
      }
      leave_approval_steps: {
        Row: {
          decided_at: string | null
          decided_by: string | null
          due_at: string | null
          id: string
          leave_id: string
          level: string
          note: string | null
          status: string
          step: number
          via_delegation: boolean
        }
        ComputedFields: never
        Insert: {
          decided_at?: string | null
          decided_by?: string | null
          due_at?: string | null
          id?: string
          leave_id: string
          level: string
          note?: string | null
          status?: string
          step: number
          via_delegation?: boolean
        }
        Update: {
          decided_at?: string | null
          decided_by?: string | null
          due_at?: string | null
          id?: string
          leave_id?: string
          level?: string
          note?: string | null
          status?: string
          step?: number
          via_delegation?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "leave_approval_steps_leave_id_fkey"
            columns: ["leave_id"]
            isOneToOne: false
            referencedRelation: "leave_applications"
            referencedColumns: ["id"]
          },
        ]
      }
      leave_ledger: {
        Row: {
          created_at: string
          created_by: string | null
          days: number
          effective_date: string
          employee_id: string
          id: string
          kind: string
          leave_type: string
          note: string | null
          source_id: string | null
          source_table: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          created_by?: string | null
          days: number
          effective_date: string
          employee_id: string
          id?: string
          kind: string
          leave_type: string
          note?: string | null
          source_id?: string | null
          source_table: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          days?: number
          effective_date?: string
          employee_id?: string
          id?: string
          kind?: string
          leave_type?: string
          note?: string | null
          source_id?: string | null
          source_table?: string
        }
        Relationships: [
          {
            foreignKeyName: "leave_ledger_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leave_ledger_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "leave_ledger_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "leave_ledger_leave_type_fkey"
            columns: ["leave_type"]
            isOneToOne: false
            referencedRelation: "leave_types"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "leave_ledger_leave_type_fkey"
            columns: ["leave_type"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["leave_type"]
          },
        ]
      }
      leave_types: {
        Row: {
          affects_payroll: string
          code: string
          created_at: string
          days_per_month: number
          extension_days: number
          is_paid: boolean
          max_days_per_year: number | null
          name: string
        }
        ComputedFields: never
        Insert: {
          affects_payroll?: string
          code: string
          created_at?: string
          days_per_month?: number
          extension_days?: number
          is_paid?: boolean
          max_days_per_year?: number | null
          name: string
        }
        Update: {
          affects_payroll?: string
          code?: string
          created_at?: string
          days_per_month?: number
          extension_days?: number
          is_paid?: boolean
          max_days_per_year?: number | null
          name?: string
        }
        Relationships: []
      }
      legal_sources: {
        Row: {
          article: string | null
          code: string
          created_at: string
          document: string | null
          label: string
          notes: string | null
          source_type: string
          status: string
          valid_from: string | null
        }
        ComputedFields: never
        Insert: {
          article?: string | null
          code: string
          created_at?: string
          document?: string | null
          label: string
          notes?: string | null
          source_type: string
          status?: string
          valid_from?: string | null
        }
        Update: {
          article?: string | null
          code?: string
          created_at?: string
          document?: string | null
          label?: string
          notes?: string | null
          source_type?: string
          status?: string
          valid_from?: string | null
        }
        Relationships: []
      }
      loan_installments: {
        Row: {
          amount: number
          applied_period: string | null
          due_period: string
          id: string
          loan_id: string
          status: string
        }
        ComputedFields: never
        Insert: {
          amount: number
          applied_period?: string | null
          due_period: string
          id?: string
          loan_id: string
          status?: string
        }
        Update: {
          amount?: number
          applied_period?: string | null
          due_period?: string
          id?: string
          loan_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "loan_installments_loan_id_fkey"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "loan_balances"
            referencedColumns: ["loan_id"]
          },
          {
            foreignKeyName: "loan_installments_loan_id_fkey"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "loans"
            referencedColumns: ["id"]
          },
        ]
      }
      loans: {
        Row: {
          cancel_reason: string | null
          created_at: string
          created_by: string | null
          employee_id: string
          first_period: string
          id: string
          installments: number
          label: string
          principal: number
          request_id: string | null
          status: string
        }
        ComputedFields: never
        Insert: {
          cancel_reason?: string | null
          created_at?: string
          created_by?: string | null
          employee_id: string
          first_period: string
          id?: string
          installments: number
          label: string
          principal: number
          request_id?: string | null
          status?: string
        }
        Update: {
          cancel_reason?: string | null
          created_at?: string
          created_by?: string | null
          employee_id?: string
          first_period?: string
          id?: string
          installments?: number
          label?: string
          principal?: number
          request_id?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "loans_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loans_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "loans_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "loans_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "employee_requests"
            referencedColumns: ["id"]
          },
        ]
      }
      module_activation: {
        Row: {
          disabled_at: string | null
          enabled: boolean
          enabled_at: string | null
          enabled_by: string | null
          id: string
          manifest_hash: string | null
          manifest_version: string | null
          module_id: string
        }
        ComputedFields: never
        Insert: {
          disabled_at?: string | null
          enabled?: boolean
          enabled_at?: string | null
          enabled_by?: string | null
          id?: string
          manifest_hash?: string | null
          manifest_version?: string | null
          module_id: string
        }
        Update: {
          disabled_at?: string | null
          enabled?: boolean
          enabled_at?: string | null
          enabled_by?: string | null
          id?: string
          manifest_hash?: string | null
          manifest_version?: string | null
          module_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "module_activation_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: true
            referencedRelation: "module_manifest"
            referencedColumns: ["module_id"]
          },
        ]
      }
      module_manifest: {
        Row: {
          hash: string
          loaded_at: string
          manifest: NonNullable<Json>
          module_id: string
          name: string
          status: string
          version: string
        }
        ComputedFields: never
        Insert: {
          hash: string
          loaded_at?: string
          manifest: NonNullable<Json>
          module_id: string
          name: string
          status?: string
          version: string
        }
        Update: {
          hash?: string
          loaded_at?: string
          manifest?: NonNullable<Json>
          module_id?: string
          name?: string
          status?: string
          version?: string
        }
        Relationships: []
      }
      module_parameter_value: {
        Row: {
          entered_at: string
          entered_by: string | null
          id: string
          legal_status: string
          module_id: string
          param_key: string
          source: string | null
          valid_from: string | null
          valid_to: string | null
          value: NonNullable<Json>
        }
        ComputedFields: never
        Insert: {
          entered_at?: string
          entered_by?: string | null
          id?: string
          legal_status: string
          module_id: string
          param_key: string
          source?: string | null
          valid_from?: string | null
          valid_to?: string | null
          value: NonNullable<Json>
        }
        Update: {
          entered_at?: string
          entered_by?: string | null
          id?: string
          legal_status?: string
          module_id?: string
          param_key?: string
          source?: string | null
          valid_from?: string | null
          valid_to?: string | null
          value?: NonNullable<Json>
        }
        Relationships: [
          {
            foreignKeyName: "module_parameter_value_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "module_manifest"
            referencedColumns: ["module_id"]
          },
        ]
      }
      module_payroll_input: {
        Row: {
          employee_id: string
          entered_at: string
          entered_by: string | null
          id: string
          input_key: string
          module_id: string
          period: string
          value: number
        }
        ComputedFields: never
        Insert: {
          employee_id: string
          entered_at?: string
          entered_by?: string | null
          id?: string
          input_key: string
          module_id: string
          period: string
          value: number
        }
        Update: {
          employee_id?: string
          entered_at?: string
          entered_by?: string | null
          id?: string
          input_key?: string
          module_id?: string
          period?: string
          value?: number
        }
        Relationships: [
          {
            foreignKeyName: "module_payroll_input_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "module_payroll_input_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "module_payroll_input_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "module_payroll_input_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "module_manifest"
            referencedColumns: ["module_id"]
          },
        ]
      }
      module_shift: {
        Row: {
          created_at: string
          created_by: string | null
          employee_id: string
          hours: number
          id: string
          module_id: string
          night_hours: number
          shift_code: string
          work_date: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          created_by?: string | null
          employee_id: string
          hours: number
          id?: string
          module_id: string
          night_hours?: number
          shift_code: string
          work_date: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          employee_id?: string
          hours?: number
          id?: string
          module_id?: string
          night_hours?: number
          shift_code?: string
          work_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "module_shift_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "module_shift_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "module_shift_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "module_shift_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "module_manifest"
            referencedColumns: ["module_id"]
          },
        ]
      }
      notice_scales: {
        Row: {
          agreement_code: string | null
          category: string
          free_days_week: number
          id: string
          notice_months: number
          source_code: string | null
          valid_from: string
        }
        ComputedFields: never
        Insert: {
          agreement_code?: string | null
          category: string
          free_days_week?: number
          id?: string
          notice_months: number
          source_code?: string | null
          valid_from?: string
        }
        Update: {
          agreement_code?: string | null
          category?: string
          free_days_week?: number
          id?: string
          notice_months?: number
          source_code?: string | null
          valid_from?: string
        }
        Relationships: [
          {
            foreignKeyName: "notice_scales_agreement_code_fkey"
            columns: ["agreement_code"]
            isOneToOne: false
            referencedRelation: "collective_agreements"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "notice_scales_source_code_fkey"
            columns: ["source_code"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["code"]
          },
        ]
      }
      notifications_log: {
        Row: {
          attempts: number
          created_at: string
          data: NonNullable<Json>
          id: string
          last_error: string | null
          max_attempts: number
          message: string
          processed_at: string | null
          scheduled_at: string | null
          sent_at: string | null
          status: string
          title: string
          type: string
          user_id: string
        }
        ComputedFields: never
        Insert: {
          attempts?: number
          created_at?: string
          data?: NonNullable<Json>
          id?: string
          last_error?: string | null
          max_attempts?: number
          message: string
          processed_at?: string | null
          scheduled_at?: string | null
          sent_at?: string | null
          status?: string
          title: string
          type: string
          user_id: string
        }
        Update: {
          attempts?: number
          created_at?: string
          data?: NonNullable<Json>
          id?: string
          last_error?: string | null
          max_attempts?: number
          message?: string
          processed_at?: string | null
          scheduled_at?: string | null
          sent_at?: string | null
          status?: string
          title?: string
          type?: string
          user_id?: string
        }
        Relationships: []
      }
      org_positions: {
        Row: {
          created_at: string
          created_by: string | null
          designation_id: string
          headcount: number
          id: string
          note: string | null
          unit_id: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          created_by?: string | null
          designation_id: string
          headcount: number
          id?: string
          note?: string | null
          unit_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          designation_id?: string
          headcount?: number
          id?: string
          note?: string | null
          unit_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "org_positions_designation_id_fkey"
            columns: ["designation_id"]
            isOneToOne: false
            referencedRelation: "designations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_positions_unit_id_fkey"
            columns: ["unit_id"]
            isOneToOne: false
            referencedRelation: "departments"
            referencedColumns: ["id"]
          },
        ]
      }
      org_relations: {
        Row: {
          allocation_pct: number | null
          created_at: string
          created_by: string | null
          employee_id: string
          end_date: string | null
          id: string
          note: string | null
          related_employee_id: string
          relation_type: string
          start_date: string
        }
        ComputedFields: never
        Insert: {
          allocation_pct?: number | null
          created_at?: string
          created_by?: string | null
          employee_id: string
          end_date?: string | null
          id?: string
          note?: string | null
          related_employee_id: string
          relation_type: string
          start_date: string
        }
        Update: {
          allocation_pct?: number | null
          created_at?: string
          created_by?: string | null
          employee_id?: string
          end_date?: string | null
          id?: string
          note?: string | null
          related_employee_id?: string
          relation_type?: string
          start_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "org_relations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_relations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "org_relations_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "org_relations_related_employee_id_fkey"
            columns: ["related_employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "org_relations_related_employee_id_fkey"
            columns: ["related_employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "org_relations_related_employee_id_fkey"
            columns: ["related_employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      overtime_rates: {
        Row: {
          code: string
          effective_from: string
          hours_from: number | null
          hours_to: number | null
          label: string
          legal_min_source: string | null
          legal_min_uplift: number
          rate_uplift: number
          source_code: string | null
        }
        ComputedFields: never
        Insert: {
          code: string
          effective_from?: string
          hours_from?: number | null
          hours_to?: number | null
          label: string
          legal_min_source?: string | null
          legal_min_uplift?: number
          rate_uplift: number
          source_code?: string | null
        }
        Update: {
          code?: string
          effective_from?: string
          hours_from?: number | null
          hours_to?: number | null
          label?: string
          legal_min_source?: string | null
          legal_min_uplift?: number
          rate_uplift?: number
          source_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "overtime_rates_legal_min_source_fkey"
            columns: ["legal_min_source"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "overtime_rates_source_code_fkey"
            columns: ["source_code"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["code"]
          },
        ]
      }
      parameter_catalog: {
        Row: {
          code: string
          column_name: string
          default_value: number
          domain: string
          label: string
          legal_text: string | null
          max_value: number | null
          min_value: number | null
          sort: number
          source_code: string | null
          store: string
          unit: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          code: string
          column_name: string
          default_value: number
          domain: string
          label: string
          legal_text?: string | null
          max_value?: number | null
          min_value?: number | null
          sort?: number
          source_code?: string | null
          store: string
          unit: string
          updated_at?: string
        }
        Update: {
          code?: string
          column_name?: string
          default_value?: number
          domain?: string
          label?: string
          legal_text?: string | null
          max_value?: number | null
          min_value?: number | null
          sort?: number
          source_code?: string | null
          store?: string
          unit?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "parameter_catalog_source_code_fkey"
            columns: ["source_code"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["code"]
          },
        ]
      }
      payment_modes: {
        Row: {
          code: string
          created_at: string
          is_active: boolean
          label: string
          sort_order: number
          updated_at: string
          updated_by: string | null
        }
        ComputedFields: never
        Insert: {
          code: string
          created_at?: string
          is_active?: boolean
          label: string
          sort_order?: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          is_active?: boolean
          label?: string
          sort_order?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      payroll_anomalies: {
        Row: {
          code: string
          created_at: string
          employee_id: string | null
          id: string
          message: string
          payroll_entry_id: string
          resolution_note: string | null
          resolved_at: string | null
          resolved_by: string | null
          severity: string
          status: string
        }
        ComputedFields: never
        Insert: {
          code: string
          created_at?: string
          employee_id?: string | null
          id?: string
          message: string
          payroll_entry_id: string
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          severity: string
          status?: string
        }
        Update: {
          code?: string
          created_at?: string
          employee_id?: string | null
          id?: string
          message?: string
          payroll_entry_id?: string
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          severity?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_anomalies_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_anomalies_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "payroll_anomalies_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "payroll_anomalies_payroll_entry_id_fkey"
            columns: ["payroll_entry_id"]
            isOneToOne: false
            referencedRelation: "payroll_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      payroll_approvals: {
        Row: {
          actor_id: string
          comment: string | null
          created_at: string
          decision: string
          id: string
          payroll_entry_id: string
          role: string
        }
        ComputedFields: never
        Insert: {
          actor_id?: string
          comment?: string | null
          created_at?: string
          decision: string
          id?: string
          payroll_entry_id: string
          role: string
        }
        Update: {
          actor_id?: string
          comment?: string | null
          created_at?: string
          decision?: string
          id?: string
          payroll_entry_id?: string
          role?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_approvals_payroll_entry_id_fkey"
            columns: ["payroll_entry_id"]
            isOneToOne: false
            referencedRelation: "payroll_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      payroll_corrections: {
        Row: {
          amount: number
          applied_period: string | null
          created_at: string
          created_by: string | null
          employee_id: string
          id: string
          kind: string
          reason: string
          source_period: string
          status: string
        }
        ComputedFields: never
        Insert: {
          amount: number
          applied_period?: string | null
          created_at?: string
          created_by?: string | null
          employee_id: string
          id?: string
          kind: string
          reason: string
          source_period: string
          status?: string
        }
        Update: {
          amount?: number
          applied_period?: string | null
          created_at?: string
          created_by?: string | null
          employee_id?: string
          id?: string
          kind?: string
          reason?: string
          source_period?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_corrections_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_corrections_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "payroll_corrections_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      payroll_entries: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          closed_at: string | null
          closed_by: string | null
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          notes: string | null
          paid_at: string | null
          paid_by: string | null
          payment_mode: string
          period_end: string
          period_id: string | null
          period_start: string
          posting_date: string
          reopen_reason: string | null
          reopened_at: string | null
          reopened_by: string | null
          settings_snapshot: Json | null
          status: string
          submitted_at: string | null
          submitted_by: string | null
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          closed_at?: string | null
          closed_by?: string | null
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          notes?: string | null
          paid_at?: string | null
          paid_by?: string | null
          payment_mode?: string
          period_end: string
          period_id?: string | null
          period_start: string
          posting_date?: string
          reopen_reason?: string | null
          reopened_at?: string | null
          reopened_by?: string | null
          settings_snapshot?: Json | null
          status?: string
          submitted_at?: string | null
          submitted_by?: string | null
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          closed_at?: string | null
          closed_by?: string | null
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          notes?: string | null
          paid_at?: string | null
          paid_by?: string | null
          payment_mode?: string
          period_end?: string
          period_id?: string | null
          period_start?: string
          posting_date?: string
          reopen_reason?: string | null
          reopened_at?: string | null
          reopened_by?: string | null
          settings_snapshot?: Json | null
          status?: string
          submitted_at?: string | null
          submitted_by?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_entries_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_entries_period_id_fkey"
            columns: ["period_id"]
            isOneToOne: false
            referencedRelation: "payroll_periods"
            referencedColumns: ["id"]
          },
        ]
      }
      payroll_inputs: {
        Row: {
          absence_hours: number
          attendance_override: boolean
          created_at: string
          employee_id: string
          id: string
          leave_allowance: number
          meal_count: number
          notes: string | null
          overtime_100: number
          overtime_15: number
          overtime_40: number
          overtime_60: number
          period: string
          previous_rounding: number
          sick_leave_hours: number
          sick_leave_rate: number
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          absence_hours?: number
          attendance_override?: boolean
          created_at?: string
          employee_id: string
          id?: string
          leave_allowance?: number
          meal_count?: number
          notes?: string | null
          overtime_100?: number
          overtime_15?: number
          overtime_40?: number
          overtime_60?: number
          period: string
          previous_rounding?: number
          sick_leave_hours?: number
          sick_leave_rate?: number
          updated_at?: string
        }
        Update: {
          absence_hours?: number
          attendance_override?: boolean
          created_at?: string
          employee_id?: string
          id?: string
          leave_allowance?: number
          meal_count?: number
          notes?: string | null
          overtime_100?: number
          overtime_15?: number
          overtime_40?: number
          overtime_60?: number
          period?: string
          previous_rounding?: number
          sick_leave_hours?: number
          sick_leave_rate?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_inputs_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payroll_inputs_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "payroll_inputs_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      payroll_periods: {
        Row: {
          company_id: string
          created_at: string
          created_by: string | null
          id: string
          locked_at: string | null
          locked_by: string | null
          period_end: string
          period_start: string
          reopen_reason: string | null
          reopened_at: string | null
          reopened_by: string | null
          status: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          company_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          locked_at?: string | null
          locked_by?: string | null
          period_end: string
          period_start: string
          reopen_reason?: string | null
          reopened_at?: string | null
          reopened_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          locked_at?: string | null
          locked_by?: string | null
          period_end?: string
          period_start?: string
          reopen_reason?: string | null
          reopened_at?: string | null
          reopened_by?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_periods_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      payroll_settings: {
        Row: {
          allowance_absence_basis: string
          brs_rate: number
          cfce_rate: number
          created_at: string
          css_af_rate: number
          css_at_rate: number
          css_ceiling: number
          deduction_global_cap: number
          effective_from: string
          hourly_rate_divisor: number
          id: string
          interim_ifc_rate: number
          ipm_ceiling: number
          ipm_employee_share: number
          ipm_on_contractors: boolean
          ipm_rate: number
          ipres_rc_ceiling: number
          ipres_rc_employee_share: number
          ipres_rc_rate: number
          ipres_rg_ceiling: number
          ipres_rg_employee_share: number
          ipres_rg_rate: number
          ir_abatement_cap: number
          ir_abatement_rate: number
          km_allowance: number
          meal_allowance_factor: number
          monthly_hours: number
          precarity_rate: number
          seniority_min_years: number
          severance_basis: string
          severance_min_months: number
          smig_hourly: number
          transport_allowance: number
        }
        ComputedFields: never
        Insert: {
          allowance_absence_basis?: string
          brs_rate?: number
          cfce_rate?: number
          created_at?: string
          css_af_rate?: number
          css_at_rate?: number
          css_ceiling?: number
          deduction_global_cap?: number
          effective_from: string
          hourly_rate_divisor?: number
          id?: string
          interim_ifc_rate?: number
          ipm_ceiling?: number
          ipm_employee_share?: number
          ipm_on_contractors?: boolean
          ipm_rate?: number
          ipres_rc_ceiling?: number
          ipres_rc_employee_share?: number
          ipres_rc_rate?: number
          ipres_rg_ceiling?: number
          ipres_rg_employee_share?: number
          ipres_rg_rate?: number
          ir_abatement_cap?: number
          ir_abatement_rate?: number
          km_allowance?: number
          meal_allowance_factor?: number
          monthly_hours?: number
          precarity_rate?: number
          seniority_min_years?: number
          severance_basis?: string
          severance_min_months?: number
          smig_hourly?: number
          transport_allowance?: number
        }
        Update: {
          allowance_absence_basis?: string
          brs_rate?: number
          cfce_rate?: number
          created_at?: string
          css_af_rate?: number
          css_at_rate?: number
          css_ceiling?: number
          deduction_global_cap?: number
          effective_from?: string
          hourly_rate_divisor?: number
          id?: string
          interim_ifc_rate?: number
          ipm_ceiling?: number
          ipm_employee_share?: number
          ipm_on_contractors?: boolean
          ipm_rate?: number
          ipres_rc_ceiling?: number
          ipres_rc_employee_share?: number
          ipres_rc_rate?: number
          ipres_rg_ceiling?: number
          ipres_rg_employee_share?: number
          ipres_rg_rate?: number
          ir_abatement_cap?: number
          ir_abatement_rate?: number
          km_allowance?: number
          meal_allowance_factor?: number
          monthly_hours?: number
          precarity_rate?: number
          seniority_min_years?: number
          severance_basis?: string
          severance_min_months?: number
          smig_hourly?: number
          transport_allowance?: number
        }
        Relationships: []
      }
      payroll_snapshots: {
        Row: {
          created_at: string
          created_by: string | null
          hash_algo: string
          id: string
          payload: NonNullable<Json>
          payload_hash: string
          payroll_entry_id: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          created_by?: string | null
          hash_algo?: string
          id?: string
          payload: NonNullable<Json>
          payload_hash: string
          payroll_entry_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          hash_algo?: string
          id?: string
          payload?: NonNullable<Json>
          payload_hash?: string
          payroll_entry_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "payroll_snapshots_payroll_entry_id_fkey"
            columns: ["payroll_entry_id"]
            isOneToOne: true
            referencedRelation: "payroll_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      recurring_pay_items: {
        Row: {
          active: boolean
          amount: number
          component_code: string
          created_at: string
          created_by: string | null
          employee_id: string
          from_period: string
          id: string
          notes: string | null
          to_period: string | null
        }
        ComputedFields: never
        Insert: {
          active?: boolean
          amount: number
          component_code: string
          created_at?: string
          created_by?: string | null
          employee_id: string
          from_period: string
          id?: string
          notes?: string | null
          to_period?: string | null
        }
        Update: {
          active?: boolean
          amount?: number
          component_code?: string
          created_at?: string
          created_by?: string | null
          employee_id?: string
          from_period?: string
          id?: string
          notes?: string | null
          to_period?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "recurring_pay_items_component_code_fkey"
            columns: ["component_code"]
            isOneToOne: false
            referencedRelation: "salary_components"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "recurring_pay_items_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "recurring_pay_items_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "recurring_pay_items_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      refresh_tokens: {
        Row: {
          created_at: string
          expires_at: string
          id: string
          is_revoked: boolean
          last_used_at: string | null
          token_hash: string
          user_id: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          expires_at: string
          id?: string
          is_revoked?: boolean
          last_used_at?: string | null
          token_hash: string
          user_id: string
        }
        Update: {
          created_at?: string
          expires_at?: string
          id?: string
          is_revoked?: boolean
          last_used_at?: string | null
          token_hash?: string
          user_id?: string
        }
        Relationships: []
      }
      salary_components: {
        Row: {
          code: string
          component_type: string
          created_at: string
          description: string | null
          input_mode: string
          is_active: boolean
          name: string
          rubric_number: number | null
        }
        ComputedFields: never
        Insert: {
          code: string
          component_type: string
          created_at?: string
          description?: string | null
          input_mode?: string
          is_active?: boolean
          name: string
          rubric_number?: number | null
        }
        Update: {
          code?: string
          component_type?: string
          created_at?: string
          description?: string | null
          input_mode?: string
          is_active?: boolean
          name?: string
          rubric_number?: number | null
        }
        Relationships: []
      }
      salary_payments: {
        Row: {
          note: string | null
          paid_at: string | null
          paid_by: string | null
          payment_mode: string
          reference: string | null
          slip_id: string
          status: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          note?: string | null
          paid_at?: string | null
          paid_by?: string | null
          payment_mode: string
          reference?: string | null
          slip_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          note?: string | null
          paid_at?: string | null
          paid_by?: string | null
          payment_mode?: string
          reference?: string | null
          slip_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "salary_payments_slip_id_fkey"
            columns: ["slip_id"]
            isOneToOne: true
            referencedRelation: "salary_slips"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "salary_payments_slip_id_fkey"
            columns: ["slip_id"]
            isOneToOne: true
            referencedRelation: "v_conformite_retenues"
            referencedColumns: ["slip_id"]
          },
          {
            foreignKeyName: "salary_payments_slip_id_fkey"
            columns: ["slip_id"]
            isOneToOne: true
            referencedRelation: "v_payroll_register"
            referencedColumns: ["salary_slip_id"]
          },
          {
            foreignKeyName: "salary_payments_slip_id_fkey"
            columns: ["slip_id"]
            isOneToOne: true
            referencedRelation: "v_salary_slip_ytd"
            referencedColumns: ["salary_slip_id"]
          },
        ]
      }
      salary_slip_details: {
        Row: {
          base: number | null
          component_code: string
          deduction_amount: number
          employee_rate: number | null
          employer_amount: number
          employer_rate: number | null
          gain_amount: number
          id: string
          label: string
          quantity: number | null
          salary_slip_id: string
          section: string
          sort_order: number
        }
        ComputedFields: never
        Insert: {
          base?: number | null
          component_code: string
          deduction_amount?: number
          employee_rate?: number | null
          employer_amount?: number
          employer_rate?: number | null
          gain_amount?: number
          id?: string
          label: string
          quantity?: number | null
          salary_slip_id: string
          section: string
          sort_order: number
        }
        Update: {
          base?: number | null
          component_code?: string
          deduction_amount?: number
          employee_rate?: number | null
          employer_amount?: number
          employer_rate?: number | null
          gain_amount?: number
          id?: string
          label?: string
          quantity?: number | null
          salary_slip_id?: string
          section?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "salary_slip_details_component_code_fkey"
            columns: ["component_code"]
            isOneToOne: false
            referencedRelation: "salary_components"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "salary_slip_details_salary_slip_id_fkey"
            columns: ["salary_slip_id"]
            isOneToOne: false
            referencedRelation: "salary_slips"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "salary_slip_details_salary_slip_id_fkey"
            columns: ["salary_slip_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_retenues"
            referencedColumns: ["slip_id"]
          },
          {
            foreignKeyName: "salary_slip_details_salary_slip_id_fkey"
            columns: ["salary_slip_id"]
            isOneToOne: false
            referencedRelation: "v_payroll_register"
            referencedColumns: ["salary_slip_id"]
          },
          {
            foreignKeyName: "salary_slip_details_salary_slip_id_fkey"
            columns: ["salary_slip_id"]
            isOneToOne: false
            referencedRelation: "v_salary_slip_ytd"
            referencedColumns: ["salary_slip_id"]
          },
        ]
      }
      salary_slips: {
        Row: {
          address: string | null
          calculation: Json | null
          children_count: number | null
          contract_situation: string | null
          created_at: string
          css_base: number
          date_of_joining: string | null
          designation: string | null
          employee_id: string
          employee_name: string
          employee_number: string
          employer_charges: number
          employment_type: string | null
          grade_class: string | null
          grade_code: string | null
          gross_pay: number
          hourly_rate: number | null
          id: string
          income_tax: number
          ipm_base: number
          ipres_rc_base: number
          ipres_rg_base: number
          ir_parts: number | null
          leave_provision: number
          marital_status: string | null
          net_pay: number
          net_remuneration: number
          payment_mode: string | null
          payroll_cost: number
          payroll_entry_id: string | null
          period_end: string
          period_start: string
          precarity_provision: number
          seniority_months: number | null
          seniority_years: number | null
          spouses_count: number | null
          staff_status: string | null
          status: string
          total_employee_deductions: number
          total_net_deductions: number
          total_non_taxable: number
          trimf: number
          trimf_parts: number | null
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          address?: string | null
          calculation?: Json | null
          children_count?: number | null
          contract_situation?: string | null
          created_at?: string
          css_base?: number
          date_of_joining?: string | null
          designation?: string | null
          employee_id: string
          employee_name: string
          employee_number: string
          employer_charges?: number
          employment_type?: string | null
          grade_class?: string | null
          grade_code?: string | null
          gross_pay?: number
          hourly_rate?: number | null
          id?: string
          income_tax?: number
          ipm_base?: number
          ipres_rc_base?: number
          ipres_rg_base?: number
          ir_parts?: number | null
          leave_provision?: number
          marital_status?: string | null
          net_pay?: number
          net_remuneration?: number
          payment_mode?: string | null
          payroll_cost?: number
          payroll_entry_id?: string | null
          period_end: string
          period_start: string
          precarity_provision?: number
          seniority_months?: number | null
          seniority_years?: number | null
          spouses_count?: number | null
          staff_status?: string | null
          status?: string
          total_employee_deductions?: number
          total_net_deductions?: number
          total_non_taxable?: number
          trimf?: number
          trimf_parts?: number | null
          updated_at?: string
        }
        Update: {
          address?: string | null
          calculation?: Json | null
          children_count?: number | null
          contract_situation?: string | null
          created_at?: string
          css_base?: number
          date_of_joining?: string | null
          designation?: string | null
          employee_id?: string
          employee_name?: string
          employee_number?: string
          employer_charges?: number
          employment_type?: string | null
          grade_class?: string | null
          grade_code?: string | null
          gross_pay?: number
          hourly_rate?: number | null
          id?: string
          income_tax?: number
          ipm_base?: number
          ipres_rc_base?: number
          ipres_rg_base?: number
          ir_parts?: number | null
          leave_provision?: number
          marital_status?: string | null
          net_pay?: number
          net_remuneration?: number
          payment_mode?: string | null
          payroll_cost?: number
          payroll_entry_id?: string | null
          period_end?: string
          period_start?: string
          precarity_provision?: number
          seniority_months?: number | null
          seniority_years?: number | null
          spouses_count?: number | null
          staff_status?: string | null
          status?: string
          total_employee_deductions?: number
          total_net_deductions?: number
          total_non_taxable?: number
          trimf?: number
          trimf_parts?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "salary_slips_payroll_entry_id_fkey"
            columns: ["payroll_entry_id"]
            isOneToOne: false
            referencedRelation: "payroll_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      salary_structure_assignments: {
        Row: {
          base_salary: number | null
          created_at: string
          employee_id: string
          fees: number
          from_date: string
          id: string
          leave_paid_monthly: boolean
          notes: string | null
          other_fixed: number
          structure_id: string
          sursalaire: number
          target_net: number | null
          transport_mode: string
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          base_salary?: number | null
          created_at?: string
          employee_id: string
          fees?: number
          from_date: string
          id?: string
          leave_paid_monthly?: boolean
          notes?: string | null
          other_fixed?: number
          structure_id: string
          sursalaire?: number
          target_net?: number | null
          transport_mode?: string
          updated_at?: string
        }
        Update: {
          base_salary?: number | null
          created_at?: string
          employee_id?: string
          fees?: number
          from_date?: string
          id?: string
          leave_paid_monthly?: boolean
          notes?: string | null
          other_fixed?: number
          structure_id?: string
          sursalaire?: number
          target_net?: number | null
          transport_mode?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "salary_structure_assignments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "salary_structure_assignments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "salary_structure_assignments_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "salary_structure_assignments_structure_id_fkey"
            columns: ["structure_id"]
            isOneToOne: false
            referencedRelation: "salary_structures"
            referencedColumns: ["id"]
          },
        ]
      }
      salary_structure_components: {
        Row: {
          component_code: string
          sort_order: number
          structure_id: string
        }
        ComputedFields: never
        Insert: {
          component_code: string
          sort_order?: number
          structure_id: string
        }
        Update: {
          component_code?: string
          sort_order?: number
          structure_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "salary_structure_components_component_code_fkey"
            columns: ["component_code"]
            isOneToOne: false
            referencedRelation: "salary_components"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "salary_structure_components_structure_id_fkey"
            columns: ["structure_id"]
            isOneToOne: false
            referencedRelation: "salary_structures"
            referencedColumns: ["id"]
          },
        ]
      }
      salary_structures: {
        Row: {
          company_id: string
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
        }
        ComputedFields: never
        Insert: {
          company_id: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
        }
        Update: {
          company_id?: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
        }
        Relationships: [
          {
            foreignKeyName: "salary_structures_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      scale_catalog: {
        Row: {
          code: string
          label: string
          legal_text: string | null
          sort: number
          source_code: string | null
          updated_at: string
        }
        ComputedFields: never
        Insert: {
          code: string
          label: string
          legal_text?: string | null
          sort?: number
          source_code?: string | null
          updated_at?: string
        }
        Update: {
          code?: string
          label?: string
          legal_text?: string | null
          sort?: number
          source_code?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "scale_catalog_source_code_fkey"
            columns: ["source_code"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["code"]
          },
        ]
      }
      scale_defaults: {
        Row: {
          lines: NonNullable<Json>
          scale_code: string
        }
        ComputedFields: never
        Insert: {
          lines: NonNullable<Json>
          scale_code: string
        }
        Update: {
          lines?: NonNullable<Json>
          scale_code?: string
        }
        Relationships: [
          {
            foreignKeyName: "scale_defaults_scale_code_fkey"
            columns: ["scale_code"]
            isOneToOne: true
            referencedRelation: "scale_catalog"
            referencedColumns: ["code"]
          },
        ]
      }
      severance_scales: {
        Row: {
          effective_from: string
          id: string
          kind: string
          rate: number
          source_code: string | null
          year_from: number
          year_to: number | null
        }
        ComputedFields: never
        Insert: {
          effective_from?: string
          id?: string
          kind: string
          rate: number
          source_code?: string | null
          year_from: number
          year_to?: number | null
        }
        Update: {
          effective_from?: string
          id?: string
          kind?: string
          rate?: number
          source_code?: string | null
          year_from?: number
          year_to?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "severance_scales_source_code_fkey"
            columns: ["source_code"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["code"]
          },
        ]
      }
      statutory_notice: {
        Row: {
          amount: number
          code: string
          label: string
          source_code: string | null
          unit: string
        }
        ComputedFields: never
        Insert: {
          amount: number
          code: string
          label: string
          source_code?: string | null
          unit: string
        }
        Update: {
          amount?: number
          code?: string
          label?: string
          source_code?: string | null
          unit?: string
        }
        Relationships: [
          {
            foreignKeyName: "statutory_notice_source_code_fkey"
            columns: ["source_code"]
            isOneToOne: false
            referencedRelation: "legal_sources"
            referencedColumns: ["code"]
          },
        ]
      }
      tax_slab_brackets: {
        Row: {
          from_amount: number
          id: string
          rate: number
          slab_id: string
        }
        ComputedFields: never
        Insert: {
          from_amount: number
          id?: string
          rate: number
          slab_id: string
        }
        Update: {
          from_amount?: number
          id?: string
          rate?: number
          slab_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tax_slab_brackets_slab_id_fkey"
            columns: ["slab_id"]
            isOneToOne: false
            referencedRelation: "tax_slabs"
            referencedColumns: ["id"]
          },
        ]
      }
      tax_slabs: {
        Row: {
          created_at: string
          effective_from: string
          id: string
          name: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          effective_from: string
          id?: string
          name: string
        }
        Update: {
          created_at?: string
          effective_from?: string
          id?: string
          name?: string
        }
        Relationships: []
      }
      team_members: {
        Row: {
          allocation_pct: number
          employee_id: string
          end_date: string | null
          role_in_team: string
          start_date: string
          team_id: string
        }
        ComputedFields: never
        Insert: {
          allocation_pct?: number
          employee_id: string
          end_date?: string | null
          role_in_team?: string
          start_date?: string
          team_id: string
        }
        Update: {
          allocation_pct?: number
          employee_id?: string
          end_date?: string | null
          role_in_team?: string
          start_date?: string
          team_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "team_members_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "team_members_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "team_members_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "team_members_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
        ]
      }
      teams: {
        Row: {
          created_at: string
          created_by: string | null
          end_date: string | null
          id: string
          kind: string
          lead_employee_id: string | null
          name: string
          start_date: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          created_by?: string | null
          end_date?: string | null
          id?: string
          kind: string
          lead_employee_id?: string | null
          name: string
          start_date?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          end_date?: string | null
          id?: string
          kind?: string
          lead_employee_id?: string | null
          name?: string
          start_date?: string
        }
        Relationships: [
          {
            foreignKeyName: "teams_lead_employee_id_fkey"
            columns: ["lead_employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teams_lead_employee_id_fkey"
            columns: ["lead_employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "teams_lead_employee_id_fkey"
            columns: ["lead_employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      trainings: {
        Row: {
          created_at: string
          created_by: string | null
          description: string | null
          employee_id: string
          end_date: string | null
          id: string
          notes: string | null
          start_date: string
          status: string
          title: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          employee_id: string
          end_date?: string | null
          id?: string
          notes?: string | null
          start_date: string
          status?: string
          title: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          description?: string | null
          employee_id?: string
          end_date?: string | null
          id?: string
          notes?: string | null
          start_date?: string
          status?: string
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "trainings_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "trainings_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "trainings_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      trimf_brackets: {
        Row: {
          annual_amount: number
          id: string
          min_annual_gross: number
          per_part: boolean
          slab_id: string
        }
        ComputedFields: never
        Insert: {
          annual_amount: number
          id?: string
          min_annual_gross: number
          per_part?: boolean
          slab_id: string
        }
        Update: {
          annual_amount?: number
          id?: string
          min_annual_gross?: number
          per_part?: boolean
          slab_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "trimf_brackets_slab_id_fkey"
            columns: ["slab_id"]
            isOneToOne: false
            referencedRelation: "tax_slabs"
            referencedColumns: ["id"]
          },
        ]
      }
      user_preferences: {
        Row: {
          preferences: NonNullable<Json>
          updated_at: string
          user_id: string
        }
        ComputedFields: never
        Insert: {
          preferences?: NonNullable<Json>
          updated_at?: string
          user_id: string
        }
        Update: {
          preferences?: NonNullable<Json>
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          created_at: string
          role: string
          user_id: string
        }
        ComputedFields: never
        Insert: {
          created_at?: string
          role: string
          user_id: string
        }
        Update: {
          created_at?: string
          role?: string
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      loan_balances: {
        Row: {
          employee_id: string
          label: string
          loan_id: string
          principal: number
          prochaine_echeance: string | null
          restant: number | null
          retenu: number | null
          status: string
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "loans_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loans_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "loans_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      v_accounting_journal: {
        Row: {
          account: string | null
          credit: number | null
          debit: number | null
          journal: string | null
          label: string | null
          line_no: number | null
          payroll_entry_id: string | null
          period_start: string
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "salary_slips_payroll_entry_id_fkey"
            columns: ["payroll_entry_id"]
            isOneToOne: false
            referencedRelation: "payroll_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      v_conformite_embauche: {
        Row: {
          affiliation_hors_delai: boolean | null
          date_of_joining: string
          declaration_manquante: boolean | null
          employee_id: string
          employee_number: string
        }
        ComputedFields: never
        Insert: {
          affiliation_hors_delai?: never
          date_of_joining?: string | null
          declaration_manquante?: never
          employee_id?: string | null
          employee_number?: string | null
        }
        Update: {
          affiliation_hors_delai?: never
          date_of_joining?: string | null
          declaration_manquante?: never
          employee_id?: string | null
          employee_number?: string | null
        }
        Relationships: []
      }
      v_conformite_retenues: {
        Row: {
          assiette: number | null
          depasse_plafond_global: boolean | null
          depasse_quotite_cessible: boolean | null
          employee_id: string
          employee_number: string
          period_start: string
          plafond_global: number | null
          quotite_cessible: number | null
          retenues: number
          slip_id: string
          status: string
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      v_contribution_summary: {
        Row: {
          base_total: number | null
          component_code: string
          employee_amount: number | null
          employee_rate: number | null
          employer_amount: number | null
          employer_rate: number | null
          headcount: number | null
          label: string | null
          payroll_entry_id: string | null
          period_start: string
          sort_order: number | null
          total_amount: number | null
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "salary_slip_details_component_code_fkey"
            columns: ["component_code"]
            isOneToOne: false
            referencedRelation: "salary_components"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "salary_slips_payroll_entry_id_fkey"
            columns: ["payroll_entry_id"]
            isOneToOne: false
            referencedRelation: "payroll_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      v_echeancier_cotisations: {
        Row: {
          echeance: string | null
          effectif: number | null
          jours_restants: number | null
          majoration_estimee: number | null
          mois: string | null
          montant_du: number | null
          montant_paye: number | null
          paye_le: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      v_leave_balances: {
        Row: {
          allocated: number | null
          balance: number | null
          employee_id: string
          employee_number: string
          first_name: string
          last_name: string
          leave_type: string
          leave_type_name: string
          taken: number | null
        }
        ComputedFields: never
        Relationships: []
      }
      v_payroll_entry_payments: {
        Row: {
          paid: number | null
          payroll_entry_id: string | null
          slips: number | null
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "salary_slips_payroll_entry_id_fkey"
            columns: ["payroll_entry_id"]
            isOneToOne: false
            referencedRelation: "payroll_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      v_payroll_register: {
        Row: {
          base_salary: number | null
          brs: number | null
          cfce: number | null
          contract_situation: string | null
          css_af: number | null
          css_at: number | null
          designation: string | null
          employee_id: string
          employee_name: string
          employee_number: string
          employer_charges: number
          employment_type: string | null
          grade_code: string | null
          gross_pay: number
          income_tax: number
          ipm_employee: number | null
          ipm_employer: number | null
          ipres_rc_employee: number | null
          ipres_rc_employer: number | null
          ipres_rc_total: number | null
          ipres_rg_employee: number | null
          ipres_rg_employer: number | null
          ipres_rg_total: number | null
          is_validated: boolean | null
          km_allowance: number | null
          leave_allowance: number | null
          leave_provision: number
          meal_allowance: number | null
          net_pay: number
          net_remuneration: number
          overtime_amount: number | null
          payroll_cost: number
          payroll_entry_id: string | null
          period_start: string
          precarity_allowance: number | null
          precarity_provision: number
          previous_rounding: number | null
          salary_slip_id: string
          seniority_bonus: number | null
          staff_status: string | null
          status: string
          sursalaire: number | null
          total_employee_deductions: number
          total_net_deductions: number
          total_non_taxable: number
          transport_allowance: number | null
          trimf: number
          variable_gross: number | null
          ytd_gross: number | null
          ytd_ipres_rc: number | null
          ytd_ipres_rg: number | null
          ytd_leave_provision: number | null
          ytd_net_pay: number | null
          ytd_payroll_cost: number | null
          ytd_precarity_provision: number | null
          ytd_trimf: number | null
          ytd_validated_months: number | null
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "salary_slips_payroll_entry_id_fkey"
            columns: ["payroll_entry_id"]
            isOneToOne: false
            referencedRelation: "payroll_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      v_salary_slip_ytd: {
        Row: {
          employee_id: string
          period_start: string
          salary_slip_id: string
          ytd_gross: number | null
          ytd_income_tax: number | null
          ytd_ipres_rc: number | null
          ytd_ipres_rg: number | null
          ytd_leave_provision: number | null
          ytd_net_pay: number | null
          ytd_payroll_cost: number | null
          ytd_precarity_provision: number | null
          ytd_trimf: number | null
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "employees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_conformite_embauche"
            referencedColumns: ["employee_id"]
          },
          {
            foreignKeyName: "salary_slips_employee_id_fkey"
            columns: ["employee_id"]
            isOneToOne: false
            referencedRelation: "v_leave_balances"
            referencedColumns: ["employee_id"]
          },
        ]
      }
      v_slip_payment_status: {
        Row: {
          paid: boolean | null
          paid_at: string | null
          payment_mode: string
          payroll_entry_id: string | null
          reference: string | null
          slip_id: string
        }
        ComputedFields: never
        Relationships: [
          {
            foreignKeyName: "salary_payments_slip_id_fkey"
            columns: ["slip_id"]
            isOneToOne: true
            referencedRelation: "salary_slips"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "salary_payments_slip_id_fkey"
            columns: ["slip_id"]
            isOneToOne: true
            referencedRelation: "v_conformite_retenues"
            referencedColumns: ["slip_id"]
          },
          {
            foreignKeyName: "salary_payments_slip_id_fkey"
            columns: ["slip_id"]
            isOneToOne: true
            referencedRelation: "v_payroll_register"
            referencedColumns: ["salary_slip_id"]
          },
          {
            foreignKeyName: "salary_payments_slip_id_fkey"
            columns: ["slip_id"]
            isOneToOne: true
            referencedRelation: "v_salary_slip_ytd"
            referencedColumns: ["salary_slip_id"]
          },
          {
            foreignKeyName: "salary_slips_payroll_entry_id_fkey"
            columns: ["payroll_entry_id"]
            isOneToOne: false
            referencedRelation: "payroll_entries"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      admin_change_employee_number: {
        Args: { p_employee_id: string; p_new_number: string; p_reason: string }
        Returns: string
      }
      admin_link_employee: {
        Args: { p_employee_id: string; p_user_id: string }
        Returns: undefined
      }
      admin_list_users: {
        Args: Record<PropertyKey, never>
        Returns: {
          created_at: string
          email: string
          employee_id: string
          employee_number: string
          last_sign_in_at: string
          roles: string[]
          user_id: string
        }[]
      }
      apply_period_adjustments: {
        Args: { p_payroll_entry_id: string }
        Returns: undefined
      }
      apply_planning: { Args: { p_period: string }; Returns: Json }
      apply_request: { Args: { p_id: string }; Returns: undefined }
      approval_pending_count: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      approval_requests_overview: {
        Args: { p_status?: string }
        Returns: {
          decided_at: string
          decided_by: string
          decided_by_email: string
          decision_note: string
          id: string
          kind: string
          payload: Json
          requested_at: string
          requested_by: string
          requested_by_email: string
          status: string
          summary: string
          target: string
        }[]
      }
      archive_employee_document: {
        Args: { p_document_id: string }
        Returns: {
          archived_at: string | null
          archived_by: string | null
          checksum: string | null
          created_at: string
          created_by: string
          current_version: number
          document_slot: number
          document_type: string
          employee_id: string
          file_name: string
          id: string
          mime_type: string
          rejection_reason: string | null
          requirement_code: string | null
          size_bytes: number
          status: string
          storage_path: string
          submitted_at: string | null
          thumbnail_path: string | null
          title: string
          validated_at: string | null
          validated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "employee_documents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      assert_declaration_embauche: {
        Args: { p_entry: string }
        Returns: undefined
      }
      assign_manager_employee: {
        Args: {
          p_employee_id: string
          p_manager_employee_id: string
          p_valid_from: string
          p_valid_to?: string
        }
        Returns: {
          created_at: string
          delegated_by: string
          employee_id: string
          id: string
          manager_employee_id: string
          valid_from: string
          valid_to: string | null
        }
        SetofOptions: {
          from: "*"
          to: "employee_manager_assignments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      audit_row_hash: {
        Args: {
          p_prev: string
          r: Omit<
            Database["public"]["Tables"]["audit_log"]["Row"],
            Database["public"]["Tables"]["audit_log"]["ComputedFields"]
          >
        }
        Returns: string
      }
      audit_verify: {
        Args: Record<PropertyKey, never>
        Returns: {
          chain_pos: number
          id: number
          problem: string
        }[]
      }
      calculate_salary_slip: {
        Args: {
          p_employee_id: string
          p_payroll_entry_id?: string
          p_period_end: string
          p_period_start: string
        }
        Returns: string
      }
      can_see_leave: {
        Args: { p_employee: string; p_on: string }
        Returns: boolean
      }
      cancel_loan: {
        Args: { p_loan_id: string; p_reason: string }
        Returns: undefined
      }
      cancel_my_request: { Args: { p_request_id: string }; Returns: undefined }
      cancel_payroll_correction: {
        Args: { p_correction_id: string; p_reason: string }
        Returns: undefined
      }
      cancel_payroll_entry: {
        Args: { p_payroll_entry_id: string }
        Returns: undefined
      }
      cancel_request: { Args: { p_id: string }; Returns: undefined }
      cash_breakdown: { Args: { p_payroll_entry_id: string }; Returns: Json }
      certificat_travail: { Args: { p_employee_id: string }; Returns: string }
      check_journal_imputation: {
        Args: { p_payroll_entry_id: string }
        Returns: {
          account: string
          has_imputation: boolean
          line_no: number
          message: string
        }[]
      }
      claim_first_admin: { Args: Record<PropertyKey, never>; Returns: boolean }
      close_manager_assignment: {
        Args: { p_assignment_id: string; p_valid_to: string }
        Returns: {
          created_at: string
          delegated_by: string
          employee_id: string
          id: string
          manager_employee_id: string
          valid_from: string
          valid_to: string | null
        }
        SetofOptions: {
          from: "*"
          to: "employee_manager_assignments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      compliance_open_findings: {
        Args: Record<PropertyKey, never>
        Returns: {
          detected_on: string
          domain: string
          employee_id: string
          employee_name: string
          employee_number: string
          entity: string
          entity_id: string
          finding_id: string
          fix_target: string
          legal_ref: string
          message: string
          rule_id: string
          rule_label: string
          severity: string
          suggested_action: string
          waived: boolean
          waiver_at: string
          waiver_by: string
          waiver_id: string
          waiver_reason: string
        }[]
      }
      compliance_status: {
        Args: Record<PropertyKey, never>
        Returns: {
          nb_alertes: number
          nb_bloquants: number
          nb_derogations: number
          nb_salaries: number
          scanned_at: string
          stale: boolean
          status: string
        }[]
      }
      compute_income_tax: {
        Args: { p_date: string; p_monthly_gross: number; p_parts: number }
        Returns: Json
      }
      compute_salary_slip: {
        Args: {
          p_employee_id: string
          p_period_end: string
          p_period_start: string
          p_sursalaire?: number
        }
        Returns: Json
      }
      compute_trimf: {
        Args: { p_date: string; p_monthly_gross: number; p_parts: number }
        Returns: number
      }
      create_loan: {
        Args: {
          p_employee_id: string
          p_first_period: string
          p_installments: number
          p_label: string
          p_principal: number
          p_request_id?: string
        }
        Returns: string
      }
      create_payroll_correction: {
        Args: {
          p_amount: number
          p_employee_id: string
          p_kind: string
          p_reason: string
          p_source_period: string
        }
        Returns: string
      }
      create_payroll_snapshot: {
        Args: { p_payroll_entry_id: string }
        Returns: string
      }
      create_request: {
        Args: {
          p_kind: string
          p_payload: Json
          p_summary: string
          p_target: string
        }
        Returns: string
      }
      css_at_rate_effective: { Args: { p_default: number }; Returns: number }
      dearmor: { Args: { "": string }; Returns: string }
      decide_employee_request: {
        Args: { p_note?: string; p_request_id: string; p_status: string }
        Returns: {
          amount: number | null
          created_at: string
          decided_at: string | null
          decided_by: string | null
          decision_note: string | null
          employee_id: string
          id: string
          message: string | null
          request_type: string
          status: string
          target_date: string | null
        }
        SetofOptions: {
          from: "*"
          to: "employee_requests"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      decide_leave: {
        Args: {
          p_decision: string
          p_leave_id: string
          p_note?: string
          p_step?: number
        }
        Returns: Json
      }
      decide_request: {
        Args: { p_approve: boolean; p_id: string; p_note?: string }
        Returns: undefined
      }
      delegate_approvals: {
        Args: {
          p_delegate_user: string
          p_from: string
          p_reason?: string
          p_to: string
        }
        Returns: string
      }
      delete_payroll_entry: {
        Args: { p_payroll_entry_id: string }
        Returns: number
      }
      deroger_constat: {
        Args: { p_id: string; p_motif: string }
        Returns: undefined
      }
      detecter_conformite: { Args: Record<PropertyKey, never>; Returns: number }
      echeance_cotisations: {
        Args: { p_headcount: number; p_month: string }
        Returns: string
      }
      escalate_overdue_leave_steps: {
        Args: Record<PropertyKey, never>
        Returns: number
      }
      etat_dgid: {
        Args: { p_employee_id: string; p_period_end: string; p_type: string }
        Returns: Json
      }
      excel_datedif: {
        Args: { p_end: string; p_start: string; p_unit: string }
        Returns: number
      }
      export_ipres_css: {
        Args: { p_employee_id: string; p_period_end: string }
        Returns: string
      }
      export_payroll_journal: {
        Args: { p_payroll_entry_id: string }
        Returns: string
      }
      gen_random_uuid: { Args: Record<PropertyKey, never>; Returns: string }
      gen_salt: { Args: { "": string }; Returns: string }
      get_loan_max_rate: { Args: Record<PropertyKey, never>; Returns: number }
      grant_waiver: {
        Args: {
          p_entity_id: string
          p_parameter_code?: string
          p_reason: string
          p_rule_id: string
        }
        Returns: string
      }
      has_role: { Args: { p_roles: string[] }; Returns: boolean }
      hr_analytics: { Args: { p_months?: number }; Returns: Json }
      hr_dashboard: { Args: { p_period?: string }; Returns: Json }
      hr_dashboard_year: { Args: { p_year: number }; Returns: Json }
      hs_majoration:
        | { Args: { p_code: string; p_fallback: number }; Returns: number }
        | {
            Args: { p_code: string; p_fallback: number; p_on: string }
            Returns: number
          }
      jl_eval: { Args: { p_rule: Json; p_vars: Json }; Returns: Json }
      jl_num: { Args: { p_rule: Json; p_vars: Json }; Returns: number }
      jl_truthy: { Args: { j: Json }; Returns: boolean }
      legal_alerts: {
        Args: { p_as_of?: string; p_horizon_days?: number }
        Returns: {
          code: string
          due_date: string
          employee_id: string
          employee_name: string
          employee_number: string
          message: string
          severity: string
        }[]
      }
      lift_waivers: { Args: { p_code: string }; Returns: number }
      load_module_manifest: {
        Args: { p_hash: string; p_manifest: Json }
        Returns: Json
      }
      log_employee_document_access: {
        Args: { p_document_id: string }
        Returns: {
          accessed_at: string
          document_id: string
          id: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "employee_document_access_log"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      majoration_retard_cotisations: {
        Args: { p_amount: number; p_due_date: string; p_paid_on: string }
        Returns: number
      }
      manager_has_employee: {
        Args: { p_employee_id: string; p_on_date?: string }
        Returns: boolean
      }
      mark_employee_notification_read: {
        Args: { p_notification_id: string }
        Returns: {
          created_at: string
          id: string
          message: string
          read_at: string | null
          request_id: string | null
          title: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "employee_notifications"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      module_active_for: {
        Args: { p_employee_id: string; p_module_id: string; p_period: string }
        Returns: boolean
      }
      module_payroll_adjustments: {
        Args: { p_employee_id: string; p_hourly: number; p_period: string }
        Returns: Json
      }
      my_employee_id: { Args: Record<PropertyKey, never>; Returns: string }
      my_leave_approvals: {
        Args: Record<PropertyKey, never>
        Returns: {
          due_at: string
          employee_name: string
          employee_number: string
          from_date: string
          leave_id: string
          leave_type: string
          level: string
          overdue: boolean
          reason: string
          step: number
          to_date: string
          total_days: number
        }[]
      }
      next_employee_number: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      notify_leave_approvers: {
        Args: {
          p_leave: Omit<
            Database["public"]["Tables"]["leave_applications"]["Row"],
            Database["public"]["Tables"]["leave_applications"]["ComputedFields"]
          >
          p_level: string
          p_text: string
        }
        Returns: undefined
      }
      notify_user: {
        Args: {
          p_key: string
          p_message: string
          p_title: string
          p_user: string
        }
        Returns: undefined
      }
      org_apply_reorg: {
        Args: { p_from: string; p_moves: Json; p_reason?: string }
        Returns: number
      }
      org_attach_to_unit: {
        Args: { p_employee: string; p_link_head?: boolean; p_unit: string }
        Returns: Json
      }
      org_chart: { Args: { p_on?: string }; Returns: Json }
      org_delete_position: { Args: { p_id: string }; Returns: undefined }
      org_delete_unit: { Args: { p_id: string }; Returns: number }
      org_end_relation: {
        Args: { p_end: string; p_id: string; p_reason: string }
        Returns: undefined
      }
      org_log: {
        Args: {
          p_action: string
          p_data: Json
          p_reason: string
          p_record: string
          p_table: string
        }
        Returns: undefined
      }
      org_log_export: {
        Args: { p_format: string; p_rows: number }
        Returns: undefined
      }
      org_remove_team_member: {
        Args: { p_employee: string; p_note?: string; p_team: string }
        Returns: undefined
      }
      org_require_hr: { Args: { p_reason: string }; Returns: undefined }
      org_save_position: {
        Args: {
          p_headcount: number
          p_note?: string
          p_post: string
          p_unit: string
        }
        Returns: string
      }
      org_save_post: { Args: { p_name: string }; Returns: string }
      org_save_relation: {
        Args: {
          p_employee: string
          p_end: string
          p_id: string
          p_note: string
          p_pct: number
          p_reason: string
          p_related: string
          p_start: string
          p_type: string
        }
        Returns: string
      }
      org_save_team: {
        Args: {
          p_end: string
          p_id: string
          p_kind: string
          p_lead: string
          p_name: string
          p_reason: string
          p_start: string
        }
        Returns: string
      }
      org_save_unit: {
        Args: {
          p_head: string
          p_id: string
          p_kind: string
          p_name: string
          p_note: string
          p_parent: string
        }
        Returns: string
      }
      org_set_employee_post: {
        Args: { p_employee: string; p_post: string }
        Returns: undefined
      }
      org_set_employee_unit: {
        Args: { p_employee: string; p_note?: string; p_unit: string }
        Returns: undefined
      }
      org_set_manager: {
        Args: {
          p_employee: string
          p_from: string
          p_manager: string
          p_reason: string
        }
        Returns: string
      }
      org_set_team_member: {
        Args: {
          p_employee: string
          p_end: string
          p_pct: number
          p_reason: string
          p_role: string
          p_start: string
          p_team: string
        }
        Returns: undefined
      }
      org_set_unit_head: {
        Args: { p_employee: string; p_unit: string }
        Returns: undefined
      }
      parameter_check: {
        Args: { p_code: string; p_eff: string; p_value: number }
        Returns: undefined
      }
      parameter_overview: {
        Args: { p_as_of?: string }
        Returns: {
          code: string
          current_value: number
          default_value: number
          domain: string
          effective_from: string
          is_modified: boolean
          label: string
          legal_text: string
          max_value: number
          min_value: number
          sort: number
          source_article: string
          source_code: string
          source_document: string
          source_label: string
          source_status: string
          unit: string
        }[]
      }
      parameters_min_effective_date: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      payment_export: {
        Args: { p_mode?: string; p_payroll_entry_id: string }
        Returns: Json
      }
      payment_orders: {
        Args: { p_payroll_entry_id: string }
        Returns: {
          amount: number
          employee_id: string
          employee_name: string
          employee_number: string
          mode: string
          net_exact: number
          paid: boolean
          slip_id: string
        }[]
      }
      payment_summary: { Args: { p_payroll_entry_id: string }; Returns: Json }
      payroll_assert_separation: {
        Args: {
          p_action: string
          p_entry: Omit<
            Database["public"]["Tables"]["payroll_entries"]["Row"],
            Database["public"]["Tables"]["payroll_entries"]["ComputedFields"]
          >
          p_reason: string
        }
        Returns: undefined
      }
      payroll_closing_report: {
        Args: { p_payroll_entry_id: string }
        Returns: Json
      }
      payroll_entry_checks: {
        Args: { p_payroll_entry_id: string }
        Returns: Json
      }
      payroll_entry_comparison: {
        Args: { p_payroll_entry_id: string }
        Returns: Json
      }
      payroll_locked_until: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      payroll_settings_at: {
        Args: { p_date: string }
        Returns: {
          allowance_absence_basis: string
          brs_rate: number
          cfce_rate: number
          created_at: string
          css_af_rate: number
          css_at_rate: number
          css_ceiling: number
          deduction_global_cap: number
          effective_from: string
          hourly_rate_divisor: number
          id: string
          interim_ifc_rate: number
          ipm_ceiling: number
          ipm_employee_share: number
          ipm_on_contractors: boolean
          ipm_rate: number
          ipres_rc_ceiling: number
          ipres_rc_employee_share: number
          ipres_rc_rate: number
          ipres_rg_ceiling: number
          ipres_rg_employee_share: number
          ipres_rg_rate: number
          ir_abatement_cap: number
          ir_abatement_rate: number
          km_allowance: number
          meal_allowance_factor: number
          monthly_hours: number
          precarity_rate: number
          seniority_min_years: number
          severance_basis: string
          severance_min_months: number
          smig_hourly: number
          transport_allowance: number
        }
        SetofOptions: {
          from: "*"
          to: "payroll_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      payroll_snapshots_verify: {
        Args: Record<PropertyKey, never>
        Returns: {
          hash_algo: string
          ok: boolean
          payroll_entry_id: string
        }[]
      }
      pgp_armor_headers: {
        Args: { "": string }
        Returns: Record<string, unknown>[]
      }
      plafond_retenues: {
        Args: { p_assiette: number; p_cap?: number }
        Returns: number
      }
      plan_shifts: { Args: { p_rows: Json }; Returns: number }
      planning_compliance: {
        Args: { p_from: string; p_to: string }
        Returns: {
          code: string
          employee_id: string
          employee_name: string
          message: string
          severity: string
          week_start: string
        }[]
      }
      preavis_mois: {
        Args: { p_employee_id: string; p_on?: string }
        Returns: number
      }
      preview_employee_number: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      quotite_cessible: {
        Args: { p_assiette: number; p_kind?: string }
        Returns: number
      }
      quotite_cessible_at: {
        Args: { p_assiette: number; p_kind: string; p_on: string }
        Returns: number
      }
      reference_usage: {
        Args: { p_key: string; p_table: string }
        Returns: Json
      }
      reopen_payroll_entry: {
        Args: { p_payroll_entry_id: string; p_reason: string }
        Returns: undefined
      }
      request_parameter_change: {
        Args: { p_code: string; p_effective_from?: string; p_value: number }
        Returns: string
      }
      request_parameter_reset: {
        Args: { p_code: string; p_effective_from?: string }
        Returns: string
      }
      request_scale_change: {
        Args: { p_code: string; p_effective_from: string; p_lines: Json }
        Returns: string
      }
      request_scale_reset: {
        Args: { p_code: string; p_effective_from: string }
        Returns: string
      }
      request_waiver: {
        Args: {
          p_entity_id: string
          p_parameter_code?: string
          p_reason: string
          p_rule_id: string
        }
        Returns: string
      }
      reset_parameter: {
        Args: { p_code: string; p_effective_from?: string }
        Returns: string
      }
      revert_payroll_entry: {
        Args: {
          p_cancel_payments?: boolean
          p_payroll_entry_id: string
          p_reason: string
        }
        Returns: undefined
      }
      review_employee_document: {
        Args: { p_document_id: string; p_reason?: string; p_status: string }
        Returns: {
          archived_at: string | null
          archived_by: string | null
          checksum: string | null
          created_at: string
          created_by: string
          current_version: number
          document_slot: number
          document_type: string
          employee_id: string
          file_name: string
          id: string
          mime_type: string
          rejection_reason: string | null
          requirement_code: string | null
          size_bytes: number
          status: string
          storage_path: string
          submitted_at: string | null
          thumbnail_path: string | null
          title: string
          validated_at: string | null
          validated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "employee_documents"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      revoke_delegation: {
        Args: { p_delegation_id: string }
        Returns: undefined
      }
      revoke_waiver: {
        Args: { p_id: string; p_reason: string }
        Returns: undefined
      }
      run_compliance_scan: {
        Args: Record<PropertyKey, never>
        Returns: {
          id: string
          nb_alertes: number
          nb_bloquants: number
          nb_derogations: number
          nb_salaries: number
          scanned_at: string
          scanned_by: string | null
          status: string
          summary: NonNullable<Json>
        }
        SetofOptions: {
          from: "*"
          to: "compliance_scans"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      run_payroll_batch: {
        Args: {
          p_employee_ids?: string[]
          p_employment_type?: string
          p_payroll_entry_id: string
        }
        Returns: Json
      }
      run_payroll_entry: { Args: { p_payroll_entry_id: string }; Returns: Json }
      salary_slip_explained: { Args: { p_slip_id: string }; Returns: Json }
      scale_check_ranges: {
        Args: { p_hi: string; p_label: string; p_lines: Json; p_lo: string }
        Returns: undefined
      }
      scale_check_request: {
        Args: { p_code: string; p_effective_from: string }
        Returns: undefined
      }
      scale_get: { Args: { p_code: string; p_on?: string }; Returns: Json }
      scale_lines: { Args: { p_code: string; p_on: string }; Returns: Json }
      scale_overview: {
        Args: { p_as_of?: string }
        Returns: {
          code: string
          effective_from: string
          is_modified: boolean
          label: string
          legal_text: string
          nb_versions: number
          next_free_date: string
          sort: number
          source_article: string
          source_code: string
          source_document: string
          source_label: string
          source_status: string
        }[]
      }
      scale_reset: {
        Args: { p_code: string; p_effective_from: string }
        Returns: string
      }
      scale_save: {
        Args: { p_code: string; p_effective_from: string; p_lines: Json }
        Returns: string
      }
      scale_validate: {
        Args: { p_code: string; p_lines: Json }
        Returns: undefined
      }
      scale_version_dates: { Args: { p_code: string }; Returns: string[] }
      scale_version_locked: {
        Args: { p_from: string; p_next: string }
        Returns: boolean
      }
      scale_versions: {
        Args: { p_code: string }
        Returns: {
          effective_from: string
          locked: boolean
          nb_lines: number
        }[]
      }
      set_loan_max_rate: { Args: { p_rate: number }; Returns: number }
      set_parameter: {
        Args: { p_code: string; p_effective_from?: string; p_value: number }
        Returns: string
      }
      set_parameter_reference: {
        Args: { p_code: string; p_legal_text: string; p_source_code?: string }
        Returns: undefined
      }
      set_scale_reference: {
        Args: { p_code: string; p_legal_text: string; p_source_code?: string }
        Returns: undefined
      }
      severance_coefficient: {
        Args: { p_entry: string; p_exit: string; p_kind: string }
        Returns: number
      }
      shift_night_hours: {
        Args: { p_end: string; p_start: string }
        Returns: number
      }
      shift_templates: {
        Args: Record<PropertyKey, never>
        Returns: {
          code: string
          end_time: string
          hours: number
          label: string
          module_id: string
          night_hours: number
          start_time: string
        }[]
      }
      solde_tout_compte: { Args: { p_employee_id: string }; Returns: Json }
      solve_sursalaire_for_net: {
        Args: {
          p_employee_id: string
          p_period_end: string
          p_period_start: string
          p_target_net: number
        }
        Returns: number
      }
      sortie_salarie: {
        Args: {
          p_employee_id: string
          p_exit_date: string
          p_exit_reason: string
        }
        Returns: Json
      }
      submit_payroll_entry: {
        Args: { p_payroll_entry_id: string; p_reason?: string }
        Returns: undefined
      }
      sync_attendance_to_payroll_inputs: {
        Args: { p_period: string }
        Returns: number
      }
      tax_slab_at: { Args: { p_date: string }; Returns: string }
      transition_payroll_entry: {
        Args: {
          p_payroll_entry_id: string
          p_reason?: string
          p_target_status: string
        }
        Returns: string
      }
      try_transition_payroll_entry: {
        Args: {
          p_payroll_entry_id: string
          p_reason?: string
          p_target_status: string
        }
        Returns: Json
      }
      user_emails: {
        Args: { p_ids: string[] }
        Returns: {
          email: string
          id: string
        }[]
      }
      user_manages_employee: {
        Args: { p_employee: string; p_on: string; p_user: string }
        Returns: boolean
      }
      validate_journal_balance: {
        Args: { p_payroll_entry_id: string }
        Returns: boolean
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
