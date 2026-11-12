# IEA 15 MW turbine with the ROSCO controller in a uniform wind (9 m/s): actuator disk, k-equation RANS,
# one level of 20 m cells. One of the set-ups compared with stand-alone OpenFAST in README.md.
max_step  = 1800
stop_time = 360.0
erf.fixed_dt = 0.2          # a whole multiple of the OpenFAST step (0.005 s)

# 2400 x 1920 x 1280 m, 20 m cells on level 0; the rotor (240 m) blocks 1.8 % of the cross-section
geometry.prob_lo     = 0.    0.    0.
geometry.prob_hi     = 2400. 1920. 1280.
amr.n_cell           = 120   96    64
geometry.is_periodic = 0 1 0

# uniform inflow at xlo, outflow at xhi, no sponge
# prepare.py replaces the wind speed on the two lines marked "wind speed"
xlo.type     = "Inflow"
xlo.velocity = 9.0 0. 0.    # wind speed
xhi.type     = "Outflow"
zlo.type     = "NoSlipWall"
zhi.type     = "SlipWall"

erf.compressibility_type = Anelastic
erf.timestepping_type    = MidPoint   # the implicit vertical solve needs MidPoint
erf.vert_implicit  = true
erf.use_fft        = true

erf.dycore_horiz_adv_type  = "Upwind_5th"
erf.dycore_vert_adv_type   = "Upwind_3rd"
erf.dryscal_horiz_adv_type = "Upwind_5th"
erf.dryscal_vert_adv_type  = "Upwind_3rd"
erf.molec_diff_type = "None"
erf.les_type        = "None"

erf.init_type = "uniform"
erf.prob_name = "ABL"
prob.rho_0 = 1.225          # equals AirDens of the OpenFAST model
prob.T_0   = 300.0
prob.U_0   = 9.0            # wind speed

erf.sum_interval = -1
erf.check_int    = 900
erf.plot_file_1  = plt
erf.plot_int_1   = 1800

# the turbine: tower base raised to z = 490 m, so the hub is at mid-height (z = 640 m)
erf.moving_bodies.bodies                     = T1
erf.moving_bodies.T1.type                    = openfast_turbine
erf.moving_bodies.T1.base_pos                = 600. 960. 490.
erf.moving_bodies.T1.output_root             = T1
erf.moving_bodies.diagnostics_int            = 5
erf.moving_bodies.avg_start                  = 300.0

amr.max_level = 0

# k-equation RANS closure
erf.rans_type                     = "kEqn"
erf.rans_consistent_diffusivities = true
erf.rans_lscale_from_pblh         = false
erf.rans_lscale_min               = 1.0
erf.max_geom_lscale               = 40.0
erf.theta_ref                     = 300.0
prob.KE_0                         = 0.5
erf.plot_vars_1 = density x_velocity y_velocity z_velocity theta KE Kmv

# actuator disk; the free stream is sampled two diameters upstream and OpenFAST's
# blade-element momentum model adds the induction (AeroDyn Wake_Mod 1)
erf.moving_bodies.T1.mode                      = adm
erf.moving_bodies.T1.sampling                  = upstream
erf.moving_bodies.T1.sample_diameters_upstream = 2.0
erf.moving_bodies.T1.fst_file                  = IEA15-land-bem.fst
erf.moving_bodies.T1.num_force_points_blade    = 50
erf.moving_bodies.T1.num_points_t              = 24
erf.moving_bodies.T1.epsilon                   = 2.0      # cells of 20 m
erf.moving_bodies.wake.lines_xD                = 2 4
erf.moving_bodies.wake.int                     = 10
