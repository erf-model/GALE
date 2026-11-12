#ifndef ERF_UNIFORM_MESH_NORM_H
#define ERF_UNIFORM_MESH_NORM_H

/**
 * GALE: a kernel's normalisation on a uniform mesh, summed on one rank (moved here from
 * ERF_ActuatorSpreading, unchanged).
 */

#include <AMReX_BoxArray.H>
#include <AMReX_Geometry.H>
#include <AMReX_REAL.H>

namespace erf_actuator {

/**
 * The whole normalisation S_p of one kernel on a uniform mesh (no z_phys_nd, no detJ_cc), on any
 * rank, without communication: there a face's weight and volume depend only on the geometry, so
 * S_p is the sum of w_p dx dy dz over the faces of the domain within 3 epsilon of the point or one
 * of its periodic images (boundary faces excluded), which this rank can add up alone. The spherical
 * cut-off keeps the sum from factoring into three 1-D sums, so the faces are visited one by one,
 * as spread_partial_norms() visits them; only the order of the additions differs (a relative
 * difference of a few ulps). Returns false, leaving norm alone, when the boxes of ba (cell-centred,
 * the level's) do not cover every cell the kernel can reach: on a refined level the faces outside
 * them get no source, and spread_partial_norms() must be summed over the ranks instead.
 * A sum on the host: a caller whose source is added by a device kernel (add_scaled_kernels() on a GPU)
 * must not pair it with that source, since the two may disagree on a face at the 3 epsilon cut-off
 * (BodyExchange does not use it on a GPU build).
 * @param[out] norm the 3 components of S_p (m^3)
 */
bool uniform_mesh_norm (amrex::Real px, amrex::Real py, amrex::Real pz, amrex::Real eps,
                        const amrex::Geometry& geom, const amrex::BoxArray& ba, amrex::Real norm[3]);

} // namespace erf_actuator

#endif
