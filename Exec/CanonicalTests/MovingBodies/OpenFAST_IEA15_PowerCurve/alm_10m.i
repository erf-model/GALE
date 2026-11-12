# IEA 15 MW turbine with the ROSCO controller in a uniform wind (9 m/s): actuator line with the filtered
# lifting-line correction on two levels (20 m and a 10 m patch around the rotor).
# One of the set-ups compared with stand-alone OpenFAST in README.md.
max_step  = 1800
stop_time = 360.0
erf.fixed_dt = 0.2          # a whole multiple of the OpenFAST step (0.005 s); level 1 steps with 0.1 s

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
zlo.type     = "SlipWall"
zhi.type     = "SlipWall"

erf.anelastic      = 1
erf.anelastic_type = MidPoint   # the implicit vertical solve needs MidPoint
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

# level 1 (10 m) around the rotor; it reaches the ground, where the turbine reads the terrain height
amr.max_level        = 1
amr.ref_ratio        = 2 2 2
amr.n_error_buf      = 0
erf.refinement_indicators = box1
erf.box1.in_box_lo  = 400.  640. 0.
erf.box1.in_box_hi  = 1040. 1280. 970.
erf.box1.max_level  = 1

erf.plot_vars_1 = density x_velocity y_velocity z_velocity theta

# actuator line with the filtered lifting-line correction; OpenFAST adds no induction
# (AeroDyn Wake_Mod 0). The kernel width is 8.4 m (0.035 D, Sandia report SAND2021-15447C).
erf.moving_bodies.T1.mode                    = alm
erf.moving_bodies.T1.fst_file                = IEA15-land.fst
erf.moving_bodies.T1.num_force_points_blade  = 300    # 0.39 m apart
erf.moving_bodies.T1.epsilon                 = 0.84   # cells of 10 m
erf.moving_bodies.T1.fllc                    = true
erf.moving_bodies.T1.fllc_eps_chord          = 0.15
erf.moving_bodies.T1.fllc_eps_dr             = 3
erf.moving_bodies.T1.fllc_start_time         = 5.0
