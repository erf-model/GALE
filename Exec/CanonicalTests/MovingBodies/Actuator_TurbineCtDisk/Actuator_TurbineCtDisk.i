# Two actuator disks side by side in a uniform 10.25 m/s anelastic flow. T1 names the turbine
# table NREL_5MW_126 of GALE's library, so its rotor radius (63 m), hub height (90 m), thrust
# coefficient Ct(U) and power curve P(U) come from the table; D1 is a constant-Ct disk of the same
# size (Ct = 0.75). Both logs carry the ct and power_curve columns because one disk uses a table.
# check_turbine_disk.py requires, in every row, T1's Ct to be the table's at its free-stream speed
# and both thrusts to be 1/2 rho Ct U^2 pi R^2.

max_step = 10
stop_time = 5.0
erf.fixed_dt = 0.5

geometry.prob_lo     = 0.    0.    0.
geometry.prob_hi     = 3000. 1200. 600.
amr.n_cell           = 60    24    12
amr.max_level        = 0
geometry.is_periodic = 0 1 0
xlo.type     = "Inflow"
xlo.velocity = 10.25 0. 0.
xhi.type     = "Outflow"
zlo.type = "SlipWall"
zhi.type = "SlipWall"

erf.compressibility_type = Anelastic
erf.vert_implicit = true
erf.timestepping_type = MidPoint
erf.use_fft   = true
erf.molec_diff_type = "None"
erf.les_type        = "None"

erf.init_type = "uniform"
erf.prob_name = "ABL"
prob.rho_0 = 1.0
prob.T_0   = 300.0
prob.U_0   = 10.25

erf.sum_interval = -1
erf.check_int    = -1
erf.plot_int_1   = -1

erf.structures.model              = gale
erf.moving_bodies.bodies          = T1 D1
erf.moving_bodies.T1.type         = ct_disk
erf.moving_bodies.T1.turbine      = NREL_5MW_126   # Turbines/Data/PowerCurves/NREL_5MW_126.txt
erf.moving_bodies.T1.base_pos     = 750. 300. 0.
erf.moving_bodies.T1.epsilon      = 2.0
erf.moving_bodies.T1.air_density  = 1.0     # ERF's density here (prob.rho_0)
erf.moving_bodies.T1.output_root  = T1
erf.moving_bodies.D1.type         = ct_disk
erf.moving_bodies.D1.rotor_radius = 63.
erf.moving_bodies.D1.hub_height   = 90.
erf.moving_bodies.D1.ct           = 0.75
erf.moving_bodies.D1.base_pos     = 750. 900. 0.
erf.moving_bodies.D1.epsilon      = 2.0
erf.moving_bodies.D1.air_density  = 1.0
erf.moving_bodies.D1.output_root  = D1
