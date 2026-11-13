#ifndef ERF_ACTUATOR_RESTRICTION_H
#define ERF_ACTUATOR_RESTRICTION_H

/**
 * The bodies' momentum source from face forces, for a restart from a checkpoint of an earlier
 * version, which wrote the anchor level's face forces (moving_bodies/force_x, _y, _z) instead of
 * the source. The levels coarser than the anchor level take their source from ERF's own
 * restriction (StructureCoarseSource). This file keeps only the conversion:
 *
 *   src_f = F_f / dV_f ,   dV_f = dx dy dz (J_{m-1} + J_m) / 2
 *
 * where F_f is the force on face f (N), J_{m-1} and J_m the Jacobians (detJ) of the two cells beside
 * the face, and J = 1 without detJ (erf_actuator::face_volume).
 */

#include <AMReX_Geometry.H>
#include <AMReX_MultiFab.H>

namespace erf_actuator {

/**
 * Set src = force / dV on every valid face (N/m^3).
 * @param dir 0, 1 or 2: force and src are face-centred in direction dir and share boxes and distribution
 * @param detJ_cc cell Jacobians with one ghost cell, or nullptr on a uniform-dz mesh
 */
void face_forces_to_source (int dir, const amrex::MultiFab& force, const amrex::MultiFab* detJ_cc,
                            const amrex::Geometry& geom, amrex::MultiFab& src);

} // namespace erf_actuator

#endif
