#ifndef ERF_CELL_HEIGHTS_H
#define ERF_CELL_HEIGHTS_H

/**
 * GALE: the cell heights that limit an actuator's time step, over regions of a terrain-following or
 * stretched level (moved here from ERF_ActuatorSampling, unchanged).
 */

#include <vector>

#include <AMReX_Geometry.H>
#include <AMReX_MultiFab.H>
#include <AMReX_REAL.H>

namespace erf_actuator {

/**
 * The smallest physical cell height (the spacing of z_phys_nd's nodes along a column) in each of a
 * set of regions: region r is the box regions[6r .. 6r+2] (x, y, z low) to regions[6r+3 .. 6r+5]
 * (high), in metres. Every node column whose cells touch the region across (with a periodic x or y
 * wrapping across the seam) counts, with the spacings whose span overlaps the region's heights. On a
 * flat uniform mesh (ERF fills z_phys_nd with k dz there) that is dz to rounding. A region with a low
 * end above its high end, a non-finite bound, or no positive spacing overlapping it gets the nominal dz
 * (a folded cell's non-positive spacing is skipped), as does every region when z_phys_nd is null
 * (outside ERF, which always allocates it). A collective: the same on every rank.
 *
 * @param[in] regions 6*n bounds (m)
 * @param[out] dz n heights (m)
 */
void min_cell_heights (const amrex::MultiFab* z_phys_nd, const amrex::Geometry& geom,
                       const std::vector<amrex::Real>& regions, std::vector<amrex::Real>& dz);

/**
 * The cell height that limits a rotating blade tip, per region: the smallest dz / q_s over the cells of
 * the region (as in min_cell_heights), with q_s the largest fraction of the tip speed that can cross the
 * cell's faces. The tip's velocity is omega n x r with r in the rotor plane, so its vertical part at a
 * height Z of the disk is at most omega sqrt(R^2 - r_z^2), and r_z differs from Z - hub_z by at most the
 * blades' off-plane reach times |n_z| (the slack): q = sqrt(R^2 - d^2) / R, with d the distance from
 * the hub height to the cell's nearest point less the slack. A face of slope G (the steepest of the
 * cell's two faces, to the neighbouring nodes) is also crossed by the tip moving sideways, so
 * q_s = min(sqrt(1 + G^2), q + G): the full speed normal to the face at most. On a flat mesh a cell at
 * hub height counts its full height; on a stretched mesh the short cells low in the disk, which the tip
 * crosses moving mostly sideways, count less; on terrain the slope makes every cell count somewhat
 * more. Reads z_phys_nd's ghost nodes next to the region inside the domain and across a periodic
 * seam (FillBoundary fills them), never those outside a non-periodic side.
 * Region r is rows[9r .. 9r+8]: the box low (x, y, z), the box high, the hub height, the tip radius R
 * and the slack, in metres. The nominal dz in the same cases as min_cell_heights, and for R <= 0.
 * A collective: the same on every rank.
 *
 * @param[in] rows 9*n values (m)
 * @param[out] dz n heights (m)
 */
void tip_cell_heights (const amrex::MultiFab* z_phys_nd, const amrex::Geometry& geom,
                       const std::vector<amrex::Real>& rows, std::vector<amrex::Real>& dz);

/**
 * tip_cell_heights for every region at once: the same heights, with one device launch over the
 * columns every region covers in this rank's boxes (each column's minimum folded into its region's
 * with an atomic minimum) and one reduction over the ranks, rather than a reduction, and a device
 * synchronisation, per region. A collective: the same on every rank.
 *
 * @param[in] rows 9*n values (m), as for tip_cell_heights
 * @param[out] dz n heights (m)
 */
void tip_cell_heights_batched (const amrex::MultiFab* z_phys_nd, const amrex::Geometry& geom,
                               const std::vector<amrex::Real>& rows, std::vector<amrex::Real>& dz);

} // namespace erf_actuator

#endif
