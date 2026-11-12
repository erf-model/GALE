#ifndef ERF_ACTUATOR_RESTRICTION_H
#define ERF_ACTUATOR_RESTRICTION_H

/**
 * The bodies' momentum sources on the levels coarser than the anchor level: the anchor level's face
 * forces summed onto the coarser faces, so that every level carries the same total force.
 *
 * The bodies are spread on the anchor level only (spread_forces). A level coarser than the anchor
 * that gets no source of its own advances, and solves for its pressure, as if the bodies were not
 * there; with sub-cycling, the anchor level then takes its boundary values from a coarse flow that
 * does not feel the bodies, and the induction they cause cannot reach beyond the anchor level's
 * boxes. These functions give each coarser level the anchor level's force, face by face:
 *
 *   F_f = src_f dV_f                          (source_to_face_forces, on the anchor level)
 *   F_C = sum_f w_f F_f                       (restrict_face_forces, anchor level straight to the coarse one)
 *   src_C = F_C / dV_C                        (face_forces_to_source, on the coarse level)
 *
 * where r is the refinement ratio between the two levels (the product of the ratios between them)
 * and the sum runs, in the face's own direction, over the fine faces r I - (r-1) .. r I + (r-1)
 * with the linear (cloud-in-cell) weights w = 1 - |i - r I| / r, and across it over the r_t1 r_t2
 * fine faces that tile the coarse face. Every fine face's weights over the coarse faces add to one,
 * so the sum of F over the coarse faces equals that over the fine faces exactly (to rounding),
 * whatever the kernel width, and the linear weights keep the force's centroid in the face's own
 * direction (a body moving across a coarse cell moves its coarse source smoothly); across the face
 * the centroid may move by up to (r-1)/2 fine cells. On a terrain-following or stretched mesh dV
 * carries the cell Jacobians. A vertical force on fine faces next to a non-periodic bottom or top
 * puts part of its weight on the coarse boundary face, where the boundary condition overrides it.
 */

#include <AMReX_Geometry.H>
#include <AMReX_IntVect.H>
#include <AMReX_MultiFab.H>

namespace erf_actuator {

/**
 * Set force = src dV on every valid face (N): the force each face of grid dir carries.
 * @param dir 0, 1 or 2: src and force are face-centred in direction dir and share boxes and distribution
 * @param detJ_cc cell Jacobians with one ghost cell, or nullptr on a uniform-dz mesh
 */
void source_to_face_forces (int dir, const amrex::MultiFab& src, const amrex::MultiFab* detJ_cc,
                            const amrex::Geometry& geom, amrex::MultiFab& force);

/**
 * Set crse to the weighted sum of the fine face forces about each coarse face (see above), on
 * every valid face of crse; the coarse faces that no fine face reaches get zero. Collective.
 *
 * The fine boxes need not match the coarse level's: any layout of either works. Every face of a
 * fine box shared with its neighbour carries the same value in both copies (as spread_forces
 * leaves them), and is counted once. The faces on the outer boundary of the fine boxes should carry
 * no force (the bodies' coverage check keeps every kernel's reach inside the anchor level's boxes):
 * a force on a high one is summed here although integrate_source, which counts each box's low
 * faces only, leaves it out.
 * @param dir 0, 1 or 2: fine and crse are face-centred in direction dir
 * @param fine_geom the fine level's geometry (its periodicity)
 * @param ratio the refinement ratio between the two levels (each component >= 1)
 */
void restrict_face_forces (int dir, const amrex::MultiFab& fine, const amrex::Geometry& fine_geom,
                           const amrex::IntVect& ratio, amrex::MultiFab& crse);

/**
 * Set src = force / dV on every valid face (N/m^3).
 * @param detJ_cc cell Jacobians with one ghost cell, or nullptr on a uniform-dz mesh
 */
void face_forces_to_source (int dir, const amrex::MultiFab& force, const amrex::MultiFab* detJ_cc,
                            const amrex::Geometry& geom, amrex::MultiFab& src);

} // namespace erf_actuator

#endif
