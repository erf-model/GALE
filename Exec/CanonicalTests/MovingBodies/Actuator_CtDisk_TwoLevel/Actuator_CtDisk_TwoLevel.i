# The disk of Actuator_CtDisk_OneLevel on two levels: the same 25 m level 0 and a level 1 of 12.5 m
# cells over a tight box around the disk (x 650..850 m, 0.8 R up and down stream; y 350..850 m;
# z 0..500 m), the kernel two fine cells wide (25 m, as on one level). The disk lives on level 1;
# level 0 must carry its force too (summed onto its faces from level 1), or the coarse level's
# pressure never feels the disk and the induction stops at the fine box: the disk then sees too
# fast a flow (9.15 instead of 8.48 m/s at the disk, 9.87 instead of 9.31 m/s a quarter of a
# diameter upstream, before the fix). The two decks' disk-averaged velocities must agree.

max_step = 120
stop_time = 60.0
erf.fixed_dt = 0.5
geometry.prob_lo     = 0.    0.    0.
geometry.prob_hi     = 3000. 1200. 600.
amr.n_cell           = 120   48    24
amr.max_level        = 1
amr.ref_ratio        = 2
amr.n_error_buf      = 0
erf.refinement_indicators = rotor
erf.rotor.in_box_lo  = 650. 350. 0.
erf.rotor.in_box_hi  = 850. 850. 500.
erf.rotor.max_level  = 1
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
erf.structures.model              = gale
erf.moving_bodies.bodies          = D1
erf.moving_bodies.D1.type         = ct_disk
erf.moving_bodies.D1.base_pos     = 750. 600. 0.
erf.moving_bodies.D1.rotor_radius = 120.
erf.moving_bodies.D1.hub_height   = 300.
erf.moving_bodies.D1.ct           = 0.75
erf.moving_bodies.D1.epsilon      = 2.0
erf.moving_bodies.D1.air_density  = 1.0
erf.moving_bodies.D1.output_root  = D1
erf.moving_bodies.D1.sample_diameters_upstream = 0.25
