// GALE: the cell heights that limit an actuator's time step (moved here from ERF_ActuatorSampling,
// unchanged). horizontal_node_ranges is a verbatim copy of the helper of the same name there.

#include "ERF_CellHeights.H"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <array>
#include <limits>
#include <vector>

#include <AMReX.H>
#include <AMReX_BLProfiler.H>
#include <AMReX_Algorithm.H>
#include <AMReX_Array4.H>
#include <AMReX_Gpu.H>
#include <AMReX_MFIter.H>
#include <AMReX_ParallelDescriptor.H>
#include <AMReX_Reduce.H>

using namespace amrex;

namespace erf_actuator {

namespace {

// the mesh-wide values a cell's height needs: the inverse spacings across, the domain's node range across
// (a neighbour beyond it in a non-periodic direction is not read: a fine level may leave those ghost
// nodes at a fill value), the periodicity across, and whether each height is weighed by the tip speed
struct CellHeightMesh
{
    Real dxi0, dxi1;
    int nilo, nihi, njlo, njhi;
    bool perx, pery, weigh;
};

// one region's heights: the box's low and high z, the hub height, the tip radius and the slack
struct CellHeightRegion
{
    Real zl, zh, zc, rad, slack;
};

CellHeightMesh
cell_height_mesh (const Geometry& geom, bool weigh)
{
    const auto dxi = geom.InvCellSizeArray();
    const Box& domain = geom.Domain();
    return {dxi[0], dxi[1], domain.smallEnd(0), domain.bigEnd(0) + 1, domain.smallEnd(1), domain.bigEnd(1) + 1,
            geom.isPeriodic(0), geom.isPeriodic(1), weigh};
}

// the height of the cell above node (i,j,k) as region g counts it, or big when it does not count;
// the one expression both the per-region and the batched reduction take
AMREX_GPU_HOST_DEVICE AMREX_FORCE_INLINE
Real cell_height (Array4<Real const> const& znd, int i, int j, int k, const CellHeightRegion& g, const CellHeightMesh& m, Real big)
{
    const Real z0 = znd(i,j,k), z1 = znd(i,j,k+1);
    // a collapsed or folded cell (z1 <= z0) is not a height to count
    if (!(z1 > z0 && z1 > g.zl && z0 < g.zh)) { return big; }
    if (!m.weigh) { return z1 - z0; }
    // the cell's point nearest the hub height, less the slack; the tip's vertical
    // speed there is at most q = sqrt(rad^2 - dist^2) / rad of the full tip speed
    const Real gap = (g.zc < z0) ? z0 - g.zc : ((g.zc > z1) ? g.zc - z1 : Real(0.0));
    const Real dist = amrex::max(gap - g.slack, Real(0.0));
    const Real q = std::sqrt(amrex::max(g.rad * g.rad - dist * dist, Real(0.0))) / g.rad;
    // the steepest slope G of the cell's two faces (to the neighbouring nodes on
    // either side, inside the domain or across a periodic seam): a tip moving sideways
    // crosses a sloping face too, at most at (q + G) of the tip speed, and never
    // faster than the speed normal to the face, sqrt(1 + G^2)
    Real g2 = 0.0;
    for (int kk = k; kk <= k + 1; ++kk) {
        const Real zc0 = znd(i,j,kk);
        Real gx = 0.0, gy = 0.0;
        if ((m.perx || i + 1 <= m.nihi) && znd.contains(i+1,j,kk)) { gx = amrex::max(gx, std::abs(znd(i+1,j,kk) - zc0)); }
        if ((m.perx || i - 1 >= m.nilo) && znd.contains(i-1,j,kk)) { gx = amrex::max(gx, std::abs(zc0 - znd(i-1,j,kk))); }
        if ((m.pery || j + 1 <= m.njhi) && znd.contains(i,j+1,kk)) { gy = amrex::max(gy, std::abs(znd(i,j+1,kk) - zc0)); }
        if ((m.pery || j - 1 >= m.njlo) && znd.contains(i,j-1,kk)) { gy = amrex::max(gy, std::abs(zc0 - znd(i,j-1,kk))); }
        gx *= m.dxi0; gy *= m.dxi1;
        g2 = amrex::max(g2, gx * gx + gy * gy);
    }
    const Real qs = amrex::min(std::sqrt(Real(1.0) + g2), q + std::sqrt(g2));
    return (qs > Real(0.0)) ? (z1 - z0) / qs : big;
}

// Per direction across, the node index ranges of the cells a region touches, from its low (b[0], b[1])
// and high (b[3], b[4]) ends in metres: one range, or two in a periodic direction whose range crosses
// the seam (the part beyond it wrapped to the other side)
void
horizontal_node_ranges (const Real* b, const Geometry& geom, std::array<std::vector<std::array<int,2>>,2>& ranges)
{
    const auto plo = geom.ProbLoArray();
    const auto dxi = geom.InvCellSizeArray();
    const Box& domain = geom.Domain();
    for (int d = 0; d < 2; ++d) {
        ranges[d].clear();
        const int dlo = domain.smallEnd(d), dhi = domain.bigEnd(d), nc = dhi - dlo + 1;
        // a bound more than a domain length outside (a diverged point) is clamped there, so the
        // index stays an int; such a region already covers or misses the whole domain
        const Real len = Real(nc) / dxi[d];
        const Real blo = amrex::Clamp(b[d],   plo[d] - len, plo[d] + Real(2.0) * len);
        const Real bhi = amrex::Clamp(b[d+3], plo[d] - len, plo[d] + Real(2.0) * len);
        const int clo = static_cast<int>(std::floor((blo - plo[d]) * dxi[d]));
        const int chi = static_cast<int>(std::floor((bhi - plo[d]) * dxi[d]));
        if (geom.isPeriodic(d)) {
            const int nnodes = chi + 2 - clo;   // nodes clo .. chi + 1
            if (nnodes >= nc) {
                ranges[d].push_back({{dlo, dhi + 1}});
            } else {
                const int a = dlo + (((clo - dlo) % nc) + nc) % nc;
                const int e = a + nnodes - 1;
                if (e <= dhi + 1) {
                    ranges[d].push_back({{a, e}});
                } else {
                    ranges[d].push_back({{a, dhi + 1}});
                    ranges[d].push_back({{dlo, e - nc}});
                }
            }
        } else {
            const int a = std::max(clo, dlo), e = std::min(chi + 1, dhi + 1);
            if (a <= e) { ranges[d].push_back({{a, e}}); }
        }
    }
}

// Region b (nine values) as the reductions take it: false for one that keeps the nominal dz (empty,
// with a non-finite value or a non-positive radius); else its heights and, per direction across, the
// node index ranges of the cells it touches (horizontal_node_ranges)
bool
region_ranges (const Real* b, const Geometry& geom, CellHeightRegion& g, std::array<std::vector<std::array<int,2>>,2>& ranges)
{
    // an empty region (low end above high end), one with a non-finite value (a diverged hub) or
    // a non-positive radius keeps the nominal dz
    bool finite = true;
    for (int d = 0; d < 9; ++d) { finite = finite && std::isfinite(b[d]); }
    if (!finite || b[0] > b[3] || b[1] > b[4] || b[2] > b[5] || !(b[7] > Real(0.0))) { return false; }
    horizontal_node_ranges(b, geom, ranges);
    g = {b[2], b[5], b[6], b[7], b[8]};
    return true;
}

// the spacings from each node of the range ri x rj to the one above it, both in the node box nbx
Box
spacing_box (const Box& nbx, const std::array<int,2>& ri, const std::array<int,2>& rj)
{
    Box sbx(IntVect(ri[0], rj[0], nbx.smallEnd(2)), IntVect(ri[1], rj[1], nbx.bigEnd(2) - 1), nbx.ixType());
    sbx &= nbx;
    return sbx;
}

// the regions' minima over every rank into dz: a minimum found (below big, positive) replaces the nominal dz
void
finish_cell_heights (std::vector<Real>& found, Real big, std::vector<Real>& dz)
{
    const int n = static_cast<int>(found.size());
    ParallelDescriptor::ReduceRealMin(found.data(), n);
    for (int r = 0; r < n; ++r) {
        if (found[r] < big && found[r] > Real(0.0)) { dz[r] = found[r]; }
    }
}

// a column range of one region in one box of z_phys_nd, for the batched reduction
struct CellHeightPiece
{
    int box;      // the box's local index in z_phys_nd
    int region;
    int ilo, jlo, klo, khi;
    int nx;       // columns along x (the piece has nx times ny columns)
};

} // namespace

// Defined here, outside the anonymous namespace above: on Windows, nvcc refuses an extended
// __device__ lambda whose enclosing function has internal linkage. The helpers it calls stay
// internal, which that rule allows.
// the shared body of min_cell_heights (weigh false: every spacing in full) and tip_cell_heights:
// one reduction per region
void
cell_heights (const MultiFab* z_phys_nd, const Geometry& geom, const std::vector<Real>& rows, bool weigh, std::vector<Real>& dz)
{
    AMREX_ALWAYS_ASSERT_WITH_MESSAGE(rows.size() % 9 == 0, "tip_cell_heights: nine values per region");
    const int n = static_cast<int>(rows.size() / 9);
    const Real dz0 = static_cast<Real>(geom.CellSize(2));
    dz.assign(n, dz0);
    if (n == 0 || z_phys_nd == nullptr) { return; }
    const Real big = std::numeric_limits<Real>::max();
    const CellHeightMesh mesh = cell_height_mesh(geom, weigh);
    std::vector<Real> found(n, big);
    for (int r = 0; r < n; ++r) {
        CellHeightRegion g{};
        std::array<std::vector<std::array<int,2>>,2> ranges;
        if (!region_ranges(&rows[static_cast<std::size_t>(9 * r)], geom, g, ranges)) { continue; }
        ReduceOps<ReduceOpMin> ops;
        ReduceData<Real> data(ops);
        using T = typename decltype(data)::Type;
        for (MFIter mfi(*z_phys_nd, false); mfi.isValid(); ++mfi) {
            const Box nbx = mfi.validbox();
            Array4<Real const> const& znd = z_phys_nd->const_array(mfi);
            for (const auto& ri : ranges[0]) {
                for (const auto& rj : ranges[1]) {
                    const Box sbx = spacing_box(nbx, ri, rj);
                    if (!sbx.ok()) { continue; }
                    ops.eval(sbx, data, [=] AMREX_GPU_DEVICE (int i, int j, int k) -> T
                    {
                        return {cell_height(znd, i, j, k, g, mesh, big)};
                    });
                }
            }
        }
        found[r] = amrex::get<0>(data.value(ops));
    }
    finish_cell_heights(found, big, dz);
}

void
tip_cell_heights_batched (const MultiFab* z_phys_nd, const Geometry& geom, const std::vector<Real>& rows, std::vector<Real>& dz)
{
    BL_PROFILE("erf_actuator::tip_cell_heights_batched()");
    AMREX_ALWAYS_ASSERT_WITH_MESSAGE(rows.size() % 9 == 0, "tip_cell_heights_batched: nine values per region");
    const int n = static_cast<int>(rows.size() / 9);
    const Real dz0 = static_cast<Real>(geom.CellSize(2));
    dz.assign(n, dz0);
    if (n == 0 || z_phys_nd == nullptr) { return; }
    const Real big = std::numeric_limits<Real>::max();
    const CellHeightMesh mesh = cell_height_mesh(geom, true);
    // every region's heights and ranges, on the host
    std::vector<CellHeightRegion> regions(n, CellHeightRegion{Real(0.0), Real(0.0), Real(0.0), Real(0.0), Real(0.0)});
    std::vector<std::array<std::vector<std::array<int,2>>,2>> ranges(n);
    std::vector<char> active(n, 0);
    for (int r = 0; r < n; ++r) {
        active[r] = region_ranges(&rows[static_cast<std::size_t>(9 * r)], geom, regions[r], ranges[r]) ? 1 : 0;
    }
    // the pieces: each region's column ranges in each of this rank's boxes, with the first column of each
    // (a prefix sum over the pieces' columns)
    std::vector<CellHeightPiece> pieces;
    std::vector<Long> first{0};
    for (MFIter mfi(*z_phys_nd, false); mfi.isValid(); ++mfi) {
        const Box nbx = mfi.validbox();
        for (int r = 0; r < n; ++r) {
            if (active[r] == 0) { continue; }
            for (const auto& ri : ranges[r][0]) {
                for (const auto& rj : ranges[r][1]) {
                    const Box sbx = spacing_box(nbx, ri, rj);
                    if (!sbx.ok()) { continue; }
                    const IntVect len = sbx.length();
                    pieces.push_back({mfi.LocalIndex(), r, sbx.smallEnd(0), sbx.smallEnd(1), sbx.smallEnd(2), sbx.bigEnd(2), len[0]});
                    first.push_back(first.back() + static_cast<Long>(len[0]) * static_cast<Long>(len[1]));
                }
            }
        }
    }
    std::vector<Real> found(n, big);
    const Long ncol = first.back();
    if (ncol > 0) {
        // one launch over every column of every piece: a thread takes a column's minimum and folds it
        // into its region's with an atomic minimum (exact, so the order does not matter)
        const int npieces = static_cast<int>(pieces.size());
        Gpu::DeviceVector<CellHeightPiece> d_pieces(pieces.size());
        Gpu::DeviceVector<Long> d_first(first.size());
        Gpu::DeviceVector<CellHeightRegion> d_regions(regions.size());
        Gpu::DeviceVector<Real> d_found(found.size());
        Gpu::copyAsync(Gpu::hostToDevice, pieces.begin(), pieces.end(), d_pieces.begin());
        Gpu::copyAsync(Gpu::hostToDevice, first.begin(), first.end(), d_first.begin());
        Gpu::copyAsync(Gpu::hostToDevice, regions.begin(), regions.end(), d_regions.begin());
        Gpu::copyAsync(Gpu::hostToDevice, found.begin(), found.end(), d_found.begin());
        const CellHeightPiece* p_pieces = d_pieces.data();
        const Long* p_first = d_first.data();
        const CellHeightRegion* p_regions = d_regions.data();
        Real* p_found = d_found.data();
        auto const& znds = z_phys_nd->const_arrays();
        ParallelFor(ncol, [=] AMREX_GPU_DEVICE (Long c) noexcept
        {
            // the piece holding column c: the last whose first column is at most c
            int lo = 0, hi = npieces - 1;
            while (lo < hi) {
                const int mid = (lo + hi + 1) / 2;
                if (p_first[mid] <= c) { lo = mid; } else { hi = mid - 1; }
            }
            const CellHeightPiece& pc = p_pieces[lo];
            const Long off = c - p_first[lo];
            const int i = pc.ilo + static_cast<int>(off % pc.nx);
            const int j = pc.jlo + static_cast<int>(off / pc.nx);
            Array4<Real const> const& znd = znds[pc.box];
            const CellHeightRegion g = p_regions[pc.region];
            Real best = big;
            for (int k = pc.klo; k <= pc.khi; ++k) { best = amrex::min(best, cell_height(znd, i, j, k, g, mesh, big)); }
            if (best < big) { Gpu::Atomic::Min(p_found + pc.region, best); }
        });
        Gpu::copyAsync(Gpu::deviceToHost, d_found.begin(), d_found.end(), found.begin());
        Gpu::streamSynchronize();
    }
    finish_cell_heights(found, big, dz);
}

void
min_cell_heights (const MultiFab* z_phys_nd, const Geometry& geom, const std::vector<Real>& regions, std::vector<Real>& dz)
{
    AMREX_ALWAYS_ASSERT_WITH_MESSAGE(regions.size() % 6 == 0, "min_cell_heights: six bounds per region");
    // every spacing counts in full: a slack wider than any height keeps the distance to the "hub" zero
    const std::size_t n = regions.size() / 6;
    std::vector<Real> rows;
    rows.reserve(9 * n);
    for (std::size_t r = 0; r < n; ++r) {
        rows.insert(rows.end(), regions.begin() + static_cast<std::ptrdiff_t>(6 * r), regions.begin() + static_cast<std::ptrdiff_t>(6 * r + 6));
        rows.push_back(Real(0.0));
        rows.push_back(Real(1.0));
        rows.push_back(std::numeric_limits<Real>::max());
    }
    cell_heights(z_phys_nd, geom, rows, false, dz);
}

void
tip_cell_heights (const MultiFab* z_phys_nd, const Geometry& geom, const std::vector<Real>& rows, std::vector<Real>& dz)
{
    BL_PROFILE("erf_actuator::tip_cell_heights()");
    cell_heights(z_phys_nd, geom, rows, true, dz);
}

} // namespace erf_actuator
