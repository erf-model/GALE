# Reference for Actuator_CtDisk_TwoLevel: a prescribed uniform-Ct disk (R = 120 m, hub 300 m, Ct =
# 0.75) in a uniform 10 m/s anelastic flow, on one level of 25 m cells, the kernel one cell wide
# (25 m). The free stream is sampled a quarter of a diameter ahead of the disk. Its log (D1_disk.csv)
# gives the induction the two-level deck must reproduce.

max_step = 120
stop_time = 60.0
erf.fixed_dt = 0.5
geometry.prob_lo     = 0.    0.    0.
geometry.prob_hi     = 3000. 1200. 600.
amr.n_cell           = 120   48    24
amr.max_level        = 0
geometry.is_periodic = 0 1 0
xlo.type     = "Inflow"
xlo.velocity = 10.0 0. 0.
xhi.type     = "Outflow"
zlo.type = "SlipWall"
zhi.type = "SlipWall"
erf.compressibility_type = Anelastic
erf.vert_implicit = true
erf.timestepping_type = MidPoint
erf.use_fft   = true
erf.molec_diff_type = "None"
erf.les_type        = "None"
erf.dycore_horiz_adv_type  = "Upwind_5th"
erf.dycore_vert_adv_type   = "Upwind_3rd"
erf.init_type = "uniform"
erf.prob_name = "ABL"
prob.rho_0 = 1.0
prob.T_0   = 300.0
prob.U_0   = 10.0
erf.sum_interval = -1
erf.check_int    = -1
erf.plot_file_1  = plt
erf.plot_int_1   = -1
erf.plot_vars_1  = density x_velocity y_velocity z_velocity theta
erf.moving_bodies.bodies          = D1
erf.moving_bodies.D1.type         = ct_disk
erf.moving_bodies.D1.base_pos     = 750. 600. 0.
erf.moving_bodies.D1.rotor_radius = 120.
erf.moving_bodies.D1.hub_height   = 300.
erf.moving_bodies.D1.ct           = 0.75
erf.moving_bodies.D1.epsilon      = 1.0
erf.moving_bodies.D1.air_density  = 1.0
erf.moving_bodies.D1.output_root  = D1
erf.moving_bodies.D1.sample_diameters_upstream = 0.25
