// GALE: a kernel's normalisation on a uniform mesh (moved here from ERF_ActuatorSpreading, unchanged).
// kernel_weight, owned_faces, boundary_face and KernelFaces are verbatim copies of the helpers of the
// same names there, so the sum takes the same faces and weights as spread_partial_norms().

#include "ERF_UniformMeshNorm.H"

#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

#include <AMReX.H>
#include <AMReX_Algorithm.H>
#include <AMReX_Array4.H>
#include <AMReX_Gpu.H>

#include "ERF_ActuatorGeometry.H"
#include "ERF_ActuatorSampling.H"

using namespace amrex;

namespace erf_actuator {

namespace {

// The kernel weight exp(-r^2/eps^2) of face (i,j,k) of grid dir for the point (px,py,pz) (one
// periodic image) of width eps, 0 beyond the cut-off radius sqrt(reach2) = 3 eps
AMREX_GPU_HOST_DEVICE AMREX_FORCE_INLINE
Real kernel_weight (int dir, int i, int j, int k, Real px, Real py, Real pz,
                    const GpuArray<Real,AMREX_SPACEDIM>& plo,
                    const GpuArray<Real,AMREX_SPACEDIM>& dx,
                    Array4<Real const> const& znd, bool has_znd,
                    Real inv_eps2, Real reach2)
{
    const Real ddx = plo[0] + (i + ((dir == 0) ? Real(0.0) : Real(0.5))) * dx[0] - px;
    const Real ddy = plo[1] + (j + ((dir == 1) ? Real(0.0) : Real(0.5))) * dx[1] - py;
    const Real ddz = face_height(dir, i, j, k, znd, has_znd, plo[2], dx[2]) - pz;
    const Real r2 = ddx*ddx + ddy*ddy + ddz*ddz;
    return (r2 > reach2) ? Real(0.0) : std::exp(-r2 * inv_eps2);
}

// The faces of grid dir that a box owns: its cells' low faces, so a face shared with the next
// box (or, at a periodic end, with the first box's image) is counted once. On a non-periodic
// boundary the low domain face carries no source; the high one is never owned.
Box owned_faces (int dir, const Box& valid_cells)
{
    Box fbx = amrex::convert(valid_cells, IntVect::TheDimensionVector(dir));
    fbx.growHi(dir, -1);
    return fbx;
}

// whether face index f of grid dir lies on a non-periodic domain boundary
AMREX_GPU_HOST_DEVICE AMREX_FORCE_INLINE
bool boundary_face (int dir, int i, int j, int k, const GpuArray<int,AMREX_SPACEDIM>& per,
                    const GpuArray<int,AMREX_SPACEDIM>& dlo, const GpuArray<int,AMREX_SPACEDIM>& dhi)
{
    if (per[dir] != 0) { return false; }
    const int f = (dir == 0) ? i : ((dir == 1) ? j : k);
    return (f == dlo[dir]) || (f == dhi[dir] + 1);
}

// What the two passes over the faces share: the level's spacing, its periodicity, the bounds of a
// fitted mesh's heights over this rank's boxes, and the faces within reach of a point.
struct KernelFaces
{
    GpuArray<Real,AMREX_SPACEDIM> plo{}, dx{}, period{{0.0, 0.0, 0.0}};
    GpuArray<int,AMREX_SPACEDIM> per{{0, 0, 0}}, dlo{{0, 0, 0}}, dhi{{0, 0, 0}};
    Real dxdydz{0.0};
    bool has_znd{false}, has_detj{false};
    ZBounds zb;

    KernelFaces (const Geometry& geom, const MultiFab* z_phys_nd, const MultiFab* detJ_cc, const ZBounds* zb_local)
    {
        plo = geom.ProbLoArray();
        dx = geom.CellSizeArray();
        dxdydz = dx[0] * dx[1] * dx[2];
        for (int d = 0; d < AMREX_SPACEDIM; ++d) {
            per[d] = geom.isPeriodic(d) ? 1 : 0;
            period[d] = geom.isPeriodic(d) ? geom.ProbLength(d) : Real(0.0);
            dlo[d] = geom.Domain().smallEnd(d);
            dhi[d] = geom.Domain().bigEnd(d);
        }
        has_znd = (z_phys_nd != nullptr);
        has_detj = (detJ_cc != nullptr);
        // over this rank's boxes only: the faces this rank visits are in them, so their bounds hold. With the
        // table of its node heights they hold for any box (one aloft, a column split in z); without it the
        // bounds from the boxes that reach the ground do not hold for a box aloft over higher ground
        if (has_znd) { zb = (zb_local != nullptr) ? *zb_local : mesh_z_bounds(*z_phys_nd, geom, false); }
        if (!zb.all_ground && !zb.has_table()) { zb = ZBounds{}; }
    }

    // The index box of the faces of grid dir within reach of a point at (px,py,pz); with z_phys_nd
    // (terrain-following or stretched) a face's height is not its index times dz, so the box takes
    // every k a height within reach may lie in, from the mesh's bounds (with the table of the rank's node
    // heights where its boxes do not all reach the ground), and kernel_weight's cut-off at 3 eps, measured
    // in physical heights, picks the faces
    Box reach_box (int dir, Real px, Real py, Real pz, Real eps) const
    {
        int kb = dlo[2], kt = dhi[2];
        if (has_znd) { zb.k_range(pz - Real(3.0) * eps, pz + Real(3.0) * eps, dlo[2], dhi[2], kb, kt); }
        return reach_box_k(dir, px, py, pz, eps, kb, kt);
    }
    // The same for the three face grids, the cells in z found once
    std::array<Box,3> reach_boxes (Real px, Real py, Real pz, Real eps) const
    {
        int kb = dlo[2], kt = dhi[2];
        if (has_znd) { zb.k_range(pz - Real(3.0) * eps, pz + Real(3.0) * eps, dlo[2], dhi[2], kb, kt); }
        return {{reach_box_k(0, px, py, pz, eps, kb, kt), reach_box_k(1, px, py, pz, eps, kb, kt),
                 reach_box_k(2, px, py, pz, eps, kb, kt)}};
    }
    // reach_box with the cells [kb, kt] a height within reach may lie in (used with z_phys_nd only)
    Box reach_box_k (int dir, Real px, Real py, Real pz, Real eps, int kb, int kt) const
    {
        const Real pc[3] = {px, py, pz};
        IntVect lo, hi;
        for (int d = 0; d < 3; ++d) {
            const int reach_cells = static_cast<int>(std::ceil(Real(3.0) * eps / dx[d])) + 1;
            const Real fi = (pc[d] - plo[d]) / dx[d] - ((d == dir) ? Real(0.0) : Real(0.5));
            lo[d] = static_cast<int>(std::floor(fi)) - reach_cells;
            hi[d] = static_cast<int>(std::floor(fi)) + reach_cells + 1;
        }
        if (has_znd) {
            if (kb > kt) {
                // none of this rank's cells holds a height within reach: no face of its boxes is
                lo[2] = dhi[2] + 2;
                hi[2] = dhi[2] + 1;
                return Box(lo, hi, IntVect::TheDimensionVector(dir));
            }
            // the faces bounding those cells, one more each way for the faces of a cell's neighbours
            lo[2] = std::max(kb - 1, dlo[2]);
            hi[2] = std::min(kt + 2, dhi[2] + 1);
        }
        return Box(lo, hi, IntVect::TheDimensionVector(dir));
    }

    // The periodic images of a point that can reach the domain, appended to images: shifts of
    // -n L .. +n L per periodic direction, with n the number of domain widths its kernel reaches
    // (one unless the domain is narrower than 3 epsilon_p, as in a unit test)
    void point_images (Real px, Real py, Real pz, Real eps, std::vector<std::array<Real,3>>& images) const
    {
        int n_img[2] = {0, 0};
        for (int d = 0; d < 2; ++d) {
            if (per[d] != 0) { n_img[d] = static_cast<int>(std::ceil(Real(3.0) * eps / period[d])); }
        }
        for (int sx = -n_img[0]; sx <= n_img[0]; ++sx) {
            for (int sy = -n_img[1]; sy <= n_img[1]; ++sy) {
                images.push_back({{px + sx * period[0], py + sy * period[1], pz}});
            }
        }
    }
};

} // namespace

bool
uniform_mesh_norm (Real px, Real py, Real pz, Real eps, const Geometry& geom, const BoxArray& ba, Real norm[3])
{
    AMREX_ALWAYS_ASSERT_WITH_MESSAGE(ba.ixType().cellCentered(), "uniform_mesh_norm: the level's boxes must be cell-centred");
    KernelFaces kf(geom, nullptr, nullptr, nullptr);
    const Real inv_eps2 = Real(1.0) / (eps * eps);
    const Real reach2 = Real(9.0) * eps * eps;
    const Array4<Real const> no_znd{};
    std::vector<std::array<Real,3>> images;
    kf.point_images(px, py, pz, eps, images);
    // the faces of the domain a box would own (each physical face once): the cells' low faces
    const Box dom_cells = geom.Domain();
    // first check that the boxes hold every cell whose low face is within reach, in every direction
    for (int dir = 0; dir < 3; ++dir) {
        const Box dom_faces = owned_faces(dir, dom_cells);
        for (const auto& q : images) {
            const Box rb = kf.reach_box(dir, q[0], q[1], q[2], eps) & dom_faces;
            if (rb.isEmpty()) { continue; }
            // a face of rb and the cell it is the low face of have the same index
            if (!ba.contains(Box(rb.smallEnd(), rb.bigEnd()))) { return false; }
        }
    }
    Real s[3] = {Real(0.0), Real(0.0), Real(0.0)};
    for (int dir = 0; dir < 3; ++dir) {
        const Box dom_faces = owned_faces(dir, dom_cells);
        for (const auto& q : images) {
            const Box rb = kf.reach_box(dir, q[0], q[1], q[2], eps) & dom_faces;
            if (rb.isEmpty()) { continue; }
            const auto lo = amrex::lbound(rb);
            const auto hi = amrex::ubound(rb);
            for (int k = lo.z; k <= hi.z; ++k) {
                for (int j = lo.y; j <= hi.y; ++j) {
                    for (int i = lo.x; i <= hi.x; ++i) {
                        if (boundary_face(dir, i, j, k, kf.per, kf.dlo, kf.dhi)) { continue; }
                        const Real w = kernel_weight(dir, i, j, k, q[0], q[1], q[2], kf.plo, kf.dx, no_znd, false, inv_eps2, reach2);
                        // the product in a statement of its own, as in spread_partial_norms(): the two sums
                        // then add the same terms on a target with a fused multiply-add
                        if (w > Real(0.0)) {
                            const Real term = w * kf.dxdydz;
                            s[dir] += term;
                        }
                    }
                }
            }
        }
    }
    for (int d = 0; d < 3; ++d) { norm[d] = s[d]; }
    return true;
}

} // namespace erf_actuator
