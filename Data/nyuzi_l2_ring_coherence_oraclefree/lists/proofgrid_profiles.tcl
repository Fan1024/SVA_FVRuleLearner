# Reusable local-only ProofGrid profile for this workspace.

proc _pg_env_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

proc pg_prove_job_limit_args {} {
    set max_jobs [_pg_env_or_default PG_MEDIUM_MAX_JOBS 10]
    set per_engine [_pg_env_or_default PG_MEDIUM_PER_ENGINE_MAX_JOBS 8]

    set args [list]
    if {$max_jobs ne ""} {
        lappend args -max_jobs $max_jobs
    }
    if {$per_engine ne ""} {
        lappend args -per_engine_max_jobs $per_engine
    }
    return $args
}

proc pg_profile_apply {profile {job_prefix ""} {runtime_min_override ""}} {
    switch -- $profile {
        medium {
            set max_jobs [_pg_env_or_default PG_MEDIUM_MAX_JOBS 10]
            set per_engine [_pg_env_or_default PG_MEDIUM_PER_ENGINE_MAX_JOBS 8]
            set per_session [_pg_env_or_default PG_MEDIUM_PER_ENGINE_MAX_JOBS_PER_SESSION 10]
            set restarts [_pg_env_or_default PG_MEDIUM_RESTARTS 1]
            set prove_time [_pg_env_or_default PG_MEDIUM_PROVE_TIME_LIMIT 1H]
            set pending_time [_pg_env_or_default PG_MEDIUM_PENDING_TIME_LIMIT 20m]
            set persistent_timeout [_pg_env_or_default PG_MEDIUM_PERSISTENT_TIMEOUT 20m]
        }
        default {
            error "Unknown ProofGrid profile '$profile'. Available profiles: medium"
        }
    }

    set_proofgrid_mode local
    set_proofgrid_manager on
    set_proofgrid_restarts $restarts
    set_prove_time_limit $prove_time
    if {[info commands set_proofgrid_pending_time_limit] ne ""} {
        set_proofgrid_pending_time_limit $pending_time
    }
    if {[info commands set_persistent_proofgrid_timeout] ne ""} {
        set_persistent_proofgrid_timeout $persistent_timeout
    }
    set_proofgrid_max_jobs $max_jobs
    set_proofgrid_per_engine_max_jobs $per_engine
    set_proofgrid_per_engine_max_jobs_per_session $per_session
    if {[info commands set_proofgrid_max_local_jobs] ne ""} {
        set_proofgrid_max_local_jobs $max_jobs
    }
    if {[info commands set_proofgrid_per_engine_max_local_jobs] ne ""} {
        set_proofgrid_per_engine_max_local_jobs $per_engine
    }

    puts "pg_profile=$profile mode=local max_jobs=$max_jobs per_engine=$per_engine per_engine_per_session=$per_session restarts=$restarts prove_time_limit=$prove_time pending_time_limit=$pending_time persistent_timeout=$persistent_timeout"
}

proc pg_profile_medium {{job_prefix ""} {runtime_min_override ""}} {
    pg_profile_apply medium $job_prefix $runtime_min_override
}

proc pg_profile_medium_for_limit {prove_limit {job_prefix ""}} {
    pg_profile_medium $job_prefix
    if {[info commands set_prove_time_limit] ne ""} {
        set_prove_time_limit $prove_limit
        puts "pg_profile_prove_time_limit_override=$prove_limit"
    }
}

puts {Loaded local-only proofgrid_profiles.tcl.}
