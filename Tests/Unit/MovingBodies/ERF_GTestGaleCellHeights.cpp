// GALE's tests of the cell heights that limit an actuator's time step (GaleCore/ERF_CellHeights), and of
// the top face for sample_cell_scalar and for columns split in z (call paths only GALE's turbine module
// uses). Moved here from ERF_GTestActuatorSampling.cpp, unchanged; the mesh helpers MeshSpec and Fields
// are copies of the ones there.

#include <limits>
#include <algorithm>
#include <array>
#include <cfenv>
#include <cmath>
#include <memory>
#include <vector>

#include <AMReX_Box.H>
#include <AMReX_BoxArray.H>
#include <AMReX_BoxList.H>
#include <AMReX_DistributionMapping.H>
#include <AMReX_Geometry.H>
#include <AMReX_MultiFab.H>
#include <AMReX_ParallelDescriptor.H>
#include <AMReX_RealBox.H>

#include <gtest/gtest.h>

#include "ERF_ActuatorSampling.H"
#include "ERF_CellHeights.H"
#include "ERF_GTestThrowOnAbort.H"


namespace {

using amrex::Real;

// The linear field: (u,v,w) = c0 + cx x + cy y + cz z_phys, different coefficients per component
struct LinearField {
    std::array<Real,4> u{{ 3.0,  0.010, -0.020, 0.030}};
    std::array<Real,4> v{{-1.0, -0.005,  0.015, 0.010}};
    std::array<Real,4> w{{ 0.5,  0.002,  0.003, -0.004}};
    static Real eval (const std::array<Real,4>& c, Real x, Real y, Real z) { return c[0] + c[1]*x + c[2]*y + c[3]*z; }
};

// basic terrain-following (BTF) heights: z(x,y,eta) = h(x,y) + (H - h(x,y)) * eta, with eta the
// stretched nominal level fraction; h = 0 gives a flat stretched mesh
struct MeshSpec {
    int nx = 12, ny = 10, nz = 8;
    Real Lx = 1200.0, Ly = 1000.0, H = 400.0;
    Real stretch = 1.15;         // 1.0: uniform nominal levels
    Real hill = 0.0;             // terrain height amplitude (m); 0: flat
    std::array<int,3> max_grid{{1024, 1024, 1024}};

    Real dx () const { return Lx / nx; }
    Real dy () const { return Ly / ny; }
    Real h (Real x, Real y) const
    {
        constexpr Real pi = 3.14159265358979323846;
        return hill * (0.5 + 0.5 * std::cos(2.0 * pi * x / Lx)) * (0.5 + 0.5 * std::sin(2.0 * pi * y / Ly));
    }
    Real eta (int k) const
    {
        if (stretch == 1.0) { return Real(k) / nz; }
        return (std::pow(stretch, k) - 1.0) / (std::pow(stretch, nz) - 1.0);
    }
    Real z_node (int i, int j, int k) const
    {
        const Real x = i * dx(), y = j * dy();
        const Real hs = h(x, y);
        return hs + (H - hs) * eta(k);
    }
};

struct Fields {
    amrex::Geometry geom;
    amrex::BoxArray ba;
    amrex::DistributionMapping dm;
    amrex::MultiFab u, v, w;
    std::unique_ptr<amrex::MultiFab> znd;
    MeshSpec spec;
    LinearField lin;

    // build the mesh and fill the face velocities with the linear field at the face centres;
    // uniform_dz leaves z_phys_nd null so the sampler takes the nominal heights
    Fields (const MeshSpec& m, bool uniform_dz)
        : spec(m)
    {
        const amrex::Box domain(amrex::IntVect(0, 0, 0), amrex::IntVect(m.nx-1, m.ny-1, m.nz-1));
        const amrex::RealBox rb({AMREX_D_DECL(0.0, 0.0, 0.0)}, {AMREX_D_DECL(m.Lx, m.Ly, m.H)});
        const std::array<int,3> periodic{{0, 0, 0}};
        geom = amrex::Geometry(domain, &rb, 0, periodic.data());
        ba = amrex::BoxArray(domain);
        ba.maxSize(amrex::IntVect(m.max_grid[0], m.max_grid[1], m.max_grid[2]));
        dm = amrex::DistributionMapping(ba);
        const int ng = 2;
        u.define(amrex::convert(ba, amrex::IntVect(1,0,0)), dm, 1, ng);
        v.define(amrex::convert(ba, amrex::IntVect(0,1,0)), dm, 1, ng);
        w.define(amrex::convert(ba, amrex::IntVect(0,0,1)), dm, 1, ng);
        if (!uniform_dz) {
            znd = std::make_unique<amrex::MultiFab>(amrex::convert(ba, amrex::IntVect(1,1,1)), dm, 1, ng);
        }
        const Real dz = m.H / m.nz;
        auto node_z = [&](int i, int j, int k) { return uniform_dz ? k * dz : m.z_node(i, j, k); };
        for (amrex::MFIter mfi(u, false); mfi.isValid(); ++mfi) {
            // fill valid and ghost cells alike: the sampler reads one ghost row across box faces
            auto ua = u.array(mfi); auto va = v.array(mfi); auto wa = w.array(mfi);
            amrex::Array4<Real> za;
            if (znd) { za = znd->array(mfi); }
            const amrex::Box gbx = amrex::grow(mfi.validbox(), ng);   // x-face box grown
            const amrex::Box cbx = amrex::enclosedCells(gbx);
            amrex::LoopOnCpu(amrex::surroundingNodes(cbx), [&](int i, int j, int k) {
                if (za) { za(i,j,k) = node_z(i, j, k); }
            });
            amrex::LoopOnCpu(amrex::convert(cbx, amrex::IntVect(1,0,0)), [&](int i, int j, int k) {
                const Real x = i * m.dx(), y = (j + 0.5) * m.dy();
                const Real z = 0.25 * (node_z(i,j,k) + node_z(i,j+1,k) + node_z(i,j,k+1) + node_z(i,j+1,k+1));
                ua(i,j,k) = LinearField::eval(lin.u, x, y, z);
            });
            amrex::LoopOnCpu(amrex::convert(cbx, amrex::IntVect(0,1,0)), [&](int i, int j, int k) {
                const Real x = (i + 0.5) * m.dx(), y = j * m.dy();
                const Real z = 0.25 * (node_z(i,j,k) + node_z(i+1,j,k) + node_z(i,j,k+1) + node_z(i+1,j,k+1));
                va(i,j,k) = LinearField::eval(lin.v, x, y, z);
            });
            amrex::LoopOnCpu(amrex::convert(cbx, amrex::IntVect(0,0,1)), [&](int i, int j, int k) {
                const Real x = (i + 0.5) * m.dx(), y = (j + 0.5) * m.dy();
                const Real z = 0.25 * (node_z(i,j,k) + node_z(i+1,j,k) + node_z(i,j+1,k) + node_z(i+1,j+1,k));
                wa(i,j,k) = LinearField::eval(lin.w, x, y, z);
            });
        }
    }

    // sample the points and check every component against the analytic field
    void check (const std::vector<Real>& pos, Real tol) const
    {
        std::vector<Real> vel;
        erf_actuator::sample_velocity(u, v, w, znd.get(), geom, pos, vel);
        ASSERT_EQ(vel.size(), pos.size());
        for (std::size_t p = 0; p < pos.size() / 3; ++p) {
            SCOPED_TRACE("point " + std::to_string(p) + " at (" + std::to_string(pos[3*p]) + ", " +
                         std::to_string(pos[3*p+1]) + ", " + std::to_string(pos[3*p+2]) + ")");
            const Real x = pos[3*p], y = pos[3*p+1], z = pos[3*p+2];
            const Real eu = LinearField::eval(lin.u, x, y, z);
            const Real ev = LinearField::eval(lin.v, x, y, z);
            const Real ew = LinearField::eval(lin.w, x, y, z);
            EXPECT_NEAR(vel[3*p],   eu, tol * std::max(Real(1.0), std::abs(eu)));
            EXPECT_NEAR(vel[3*p+1], ev, tol * std::max(Real(1.0), std::abs(ev)));
            EXPECT_NEAR(vel[3*p+2], ew, tol * std::max(Real(1.0), std::abs(ew)));
        }
    }
};


// relative tolerance: each interpolation weight is exact for a linear field, so only the
// roundoff of a few dozen operations on the face values remains: far below 1e-9 in double,
// and a few units of 1e-7 in single precision, where 2e-4 leaves a wide margin
constexpr Real tol = (sizeof(Real) == 8) ? Real(1.0e-9) : Real(2.0e-4);

} // namespace

// The tests from here on are of functions and call paths only GALE's turbine module uses: the top face for
// sample_cell_scalar and for columns split in z, min_cell_heights, tip_cell_heights and tip_cell_heights_batched.

// A point on the domain's top face (a vertical wake line that reaches the top) takes the last cell: on a uniform
// mesh with the column split in z, on a stretched mesh in one box, and for a cell-centred scalar linear in z
// with the column in one box and split in z.
TEST(ActuatorSampling, TheTopFaceIsTheLastCellForASplitColumnAndACellScalar)
{
    MeshSpec m;
    m.stretch = 1.0;
    m.max_grid = {{5, 4, 1024}};
    Fields f(m, true);
    const std::vector<Real> top{Real(0.41) * m.Lx, Real(0.37) * m.Ly, m.H, m.Lx, m.Ly, m.H};
    MeshSpec ms = m;
    ms.stretch = 1.15;
    Fields fs(ms, false);
    fs.check(top, tol);
    MeshSpec mu = m;
    mu.max_grid = {{5, 4, 4}};
    Fields fu(mu, true);
    fu.check(top, tol);
    for (const Fields* fc : {&f, &fu}) {
        amrex::MultiFab c(fc->ba, fc->dm, 1, 1);
        const Real dz = m.H / m.nz;
        for (amrex::MFIter mfi(c, false); mfi.isValid(); ++mfi) {
            auto ca = c.array(mfi);
            amrex::LoopOnCpu(mfi.growntilebox(), [&](int i, int j, int k) {
                amrex::ignore_unused(i, j);
                ca(i,j,k) = Real(2.5) + Real(0.0125) * (k + Real(0.5)) * dz;
            });
        }
        std::vector<Real> val;
        erf_actuator::sample_cell_scalar(c, 0, nullptr, fc->geom, top, val);
        ASSERT_EQ(val.size(), top.size() / 3);
        for (const Real x : val) { EXPECT_NEAR(x, Real(2.5) + Real(0.0125) * m.H, tol * Real(10.0)); }
    }
}

// min_cell_heights: the shortest physical cell under a region, from z_phys_nd's node spacing; over a
// hill the cells are shorter than the nominal dz, so a rotor over the summit counts more cells than
// one over the flat; the nominal dz on a uniform-dz mesh, for an empty region, and on every rank
TEST(ActuatorSampling, TheShortestCellUnderARegionIsPhysical)
{
    MeshSpec m; m.stretch = 1.0; m.hill = 100.0; m.max_grid = {{4, 5, 3}};   // split in z too
    Fields f(m, false);
    const Real dz0 = m.H / m.nz;
    // the reference: every column whose node lies in [ilo, ihi] x [jlo, jhi], every spacing overlapping [zl, zh]
    auto brute = [&](int ilo, int ihi, int jlo, int jhi, Real zl, Real zh) {
        Real best = 1.0e30;
        for (int i = std::max(ilo, 0); i <= std::min(ihi, m.nx); ++i) {
            for (int j = std::max(jlo, 0); j <= std::min(jhi, m.ny); ++j) {
                for (int k = 0; k < m.nz; ++k) {
                    const Real z0 = m.z_node(i, j, k), z1 = m.z_node(i, j, k + 1);
                    if (z1 > zl && z0 < zh) { best = std::min(best, z1 - z0); }
                }
            }
        }
        return best;
    };
    // the summit (the hill's top at x = 0, y = Ly / 4) and a low corner (x = Lx / 2, y = 3 Ly / 4)
    const Real r = 120.0, zc = 200.0;
    const std::vector<Real> regions{
        -r, Real(0.25) * m.Ly - r, zc - r, r, Real(0.25) * m.Ly + r, zc + r,
        Real(0.5) * m.Lx - r, Real(0.75) * m.Ly - r, zc - r, Real(0.5) * m.Lx + r, Real(0.75) * m.Ly + r, zc + r,
        1.0, 1.0, 1.0, 0.0, 0.0, 0.0};
    std::vector<Real> dz;
    erf_actuator::min_cell_heights(f.znd.get(), f.geom, regions, dz);
    ASSERT_EQ(dz.size(), 3u);
    auto node = [](Real x, Real d) { return static_cast<int>(std::floor(x / d)); };
    const Real want0 = brute(node(-r, m.dx()), node(r, m.dx()) + 1, node(Real(0.25) * m.Ly - r, m.dy()),
                             node(Real(0.25) * m.Ly + r, m.dy()) + 1, zc - r, zc + r);
    const Real want1 = brute(node(Real(0.5) * m.Lx - r, m.dx()), node(Real(0.5) * m.Lx + r, m.dx()) + 1,
                             node(Real(0.75) * m.Ly - r, m.dy()), node(Real(0.75) * m.Ly + r, m.dy()) + 1, zc - r, zc + r);
    const Real tol = (sizeof(Real) == 8) ? Real(1.0e-9) : Real(1.0e-4);
    EXPECT_NEAR(dz[0], want0, tol);
    EXPECT_NEAR(dz[1], want1, tol);
    // closed form: the highest node column, x = 0 and y = 200 m (or 300 m), stands h = 100 (0.5 + 0.5 sin(0.4 pi))
    // = 97.553 m high, so its cells are (400 - h) / 8 = 37.80590 m, against the nominal 50 m
    EXPECT_NEAR(dz[0], Real(37.8058968), Real(1.0e-4));
    EXPECT_LT(dz[0], Real(0.8) * dz0);
    EXPECT_GT(dz[0], Real(0.0));
    EXPECT_GT(dz[1], dz[0] + Real(5.0)); // away from the summit the cells are taller
    EXPECT_DOUBLE_EQ(dz[2], dz0);        // an empty region
    // periodic in x: a region beyond the domain's lower x face finds the columns of its image near the
    // upper face (nodes nx - 3 to nx - 1); without the periodicity it lies outside and gets the nominal dz
    const std::array<int,3> periodic{{1, 0, 0}};
    const amrex::RealBox rb({AMREX_D_DECL(0.0, 0.0, 0.0)}, {AMREX_D_DECL(m.Lx, m.Ly, m.H)});
    const amrex::Geometry pgeom(f.geom.Domain(), &rb, 0, periodic.data());
    const std::vector<Real> beyond{Real(-2.5) * m.dx(), Real(0.25) * m.Ly - r, zc - r,
                                   Real(-1.5) * m.dx(), Real(0.25) * m.Ly + r, zc + r};
    std::vector<Real> pdz;
    erf_actuator::min_cell_heights(f.znd.get(), pgeom, beyond, pdz);
    ASSERT_EQ(pdz.size(), 1u);
    EXPECT_NEAR(pdz[0], brute(m.nx - 3, m.nx - 1, node(Real(0.25) * m.Ly - r, m.dy()), node(Real(0.25) * m.Ly + r, m.dy()) + 1,
                              zc - r, zc + r), tol);
    EXPECT_LT(pdz[0], dz0);
    erf_actuator::min_cell_heights(f.znd.get(), f.geom, beyond, pdz);
    EXPECT_DOUBLE_EQ(pdz[0], dz0);
    // a flat uniform mesh as ERF builds it, z_phys_nd = k dz with an inexact dz (400 m / 7): dz to rounding
    MeshSpec mf = m; mf.hill = 0.0; mf.nz = 7;
    Fields flat(mf, false);
    const Real dzf = mf.H / mf.nz;
    erf_actuator::min_cell_heights(flat.znd.get(), flat.geom, regions, dz);
    ASSERT_EQ(dz.size(), 3u);
    for (const Real v : dz) { EXPECT_NEAR(v, dzf, Real(1.0e-4) * dzf); }
    // a null z_phys_nd (outside ERF): the nominal dz
    Fields nominal(m, true);
    erf_actuator::min_cell_heights(nominal.znd.get(), nominal.geom, regions, dz);
    for (const Real v : dz) { EXPECT_DOUBLE_EQ(v, dz0); }
}

// min_cell_heights on a stretched mesh, where a column's cells differ: only the spacings whose span
// overlaps the region's heights count (the bottom cells under a band high in the column do not), a
// spacing at the top of a z box counts, a region straddling a periodic seam takes the columns on both
// sides, a non-finite bound keeps the nominal dz, and a folded cell is not a height
TEST(ActuatorSampling, TheShortestCellCountsOnlyTheRegionsHeightsAndBothSidesOfASeam)
{
    MeshSpec m; m.hill = 100.0; m.max_grid = {{4, 5, 3}};   // stretch 1.15; z boxes of cells 0-2, 3-5, 6-7
    Fields f(m, false);
    const Real dz0 = m.H / m.nz;
    const Real tol = (sizeof(Real) == 8) ? Real(1.0e-9) : Real(1.0e-4);
    auto brute = [&](int ilo, int ihi, int jlo, int jhi, Real zl, Real zh) {
        Real best = 1.0e30;
        for (int i = std::max(ilo, 0); i <= std::min(ihi, m.nx); ++i) {
            for (int j = std::max(jlo, 0); j <= std::min(jhi, m.ny); ++j) {
                for (int k = 0; k < m.nz; ++k) {
                    const Real z0 = m.z_node(i, j, k), z1 = m.z_node(i, j, k + 1);
                    if (z1 > zl && z0 < zh) { best = std::min(best, z1 - z0); }
                }
            }
        }
        return best;
    };
    // a band high in the summit's columns (x = -1.5 dx .. 1.5 dx, y = 2 dy .. 3 dy: nodes -2 .. 2 and 2 .. 4,
    // clipped to i = 0 .. 2 without periodicity): the bottom cells, the shortest of the stretched column,
    // lie below it and must not count
    const Real zl = 250.0, zh = 300.0;
    const std::vector<Real> band{Real(-1.5) * m.dx(), Real(2.0) * m.dy(), zl, Real(1.5) * m.dx(), Real(3.0) * m.dy(), zh};
    std::vector<Real> dz;
    erf_actuator::min_cell_heights(f.znd.get(), f.geom, band, dz);
    ASSERT_EQ(dz.size(), 1u);
    const Real want_band = brute(0, 2, 2, 4, zl, zh);
    EXPECT_NEAR(dz[0], want_band, tol);
    EXPECT_GT(dz[0], brute(0, 2, 2, 4, Real(0.0), m.H) + Real(5.0));   // the whole column's shortest is far below
    // the spacing at the top of the lowest z box (node 2 to node 3) on a flat stretched mesh, alone in the band
    MeshSpec ms = m; ms.hill = 0.0;
    Fields flat(ms, false);
    const Real z2 = ms.z_node(0, 0, 2), z3 = ms.z_node(0, 0, 3);
    const std::vector<Real> top{Real(100.0), Real(100.0), z2 + Real(0.1), Real(500.0), Real(500.0), z3 - Real(0.1)};
    erf_actuator::min_cell_heights(flat.znd.get(), flat.geom, top, dz);
    EXPECT_NEAR(dz[0], z3 - z2, tol);
    EXPECT_GT(dz[0], ms.z_node(0, 0, 1) - ms.z_node(0, 0, 0) + Real(1.0));   // not the bottom cell's height
    // periodic in y: a region straddling y = 0 (nodes -1 .. 2) takes j = ny - 1, ny and j = 0 .. 2. The hill
    // rises from y = 0 towards y = Ly / 4 and falls below it near y = Ly, so the shortest cells are on the
    // y = 0 side; the columns near y = Ly alone give taller ones
    const std::array<int,3> periodic_y{{0, 1, 0}};
    const amrex::RealBox rb({AMREX_D_DECL(0.0, 0.0, 0.0)}, {AMREX_D_DECL(m.Lx, m.Ly, m.H)});
    const amrex::Geometry pgeom(f.geom.Domain(), &rb, 0, periodic_y.data());
    const std::vector<Real> seam{Real(100.0), Real(-0.5) * m.dy(), Real(0.0), Real(300.0), Real(1.5) * m.dy(), m.H};
    erf_actuator::min_cell_heights(f.znd.get(), pgeom, seam, dz);
    const Real low_side = brute(1, 4, 0, 2, Real(0.0), m.H), high_side = brute(1, 4, m.ny - 1, m.ny, Real(0.0), m.H);
    EXPECT_NEAR(dz[0], std::min(low_side, high_side), tol);
    EXPECT_LT(low_side, high_side - Real(0.5));
    // a region wider than the periodic domain: every column
    const std::vector<Real> wide{Real(100.0), -m.Ly, Real(0.0), Real(300.0), Real(2.0) * m.Ly, m.H};
    erf_actuator::min_cell_heights(f.znd.get(), pgeom, wide, dz);
    EXPECT_NEAR(dz[0], brute(1, 4, 0, m.ny, Real(0.0), m.H), tol);
    // a huge but finite bound (a diverged hub position, 1e12 m): clamped a domain length out, so the
    // region covers every column across, as one exactly the domain wide does
    const std::vector<Real> huge{Real(-1.0e12), Real(100.0), Real(0.0), Real(1.0e12), Real(300.0), m.H};
    const std::vector<Real> whole{Real(0.0), Real(100.0), Real(0.0), m.Lx, Real(300.0), m.H};
    std::vector<Real> dzw;
    erf_actuator::min_cell_heights(f.znd.get(), f.geom, huge, dz);
    erf_actuator::min_cell_heights(f.znd.get(), f.geom, whole, dzw);
    EXPECT_EQ(dz[0], dzw[0]);
    EXPECT_LT(dz[0], dz0 - Real(5.0));
    // a non-finite bound (a diverged hub position): the nominal dz, no trap
    const std::vector<Real> bad{std::numeric_limits<Real>::quiet_NaN(), Real(0.0), Real(0.0), Real(100.0), Real(100.0), Real(100.0)};
    erf_actuator::min_cell_heights(f.znd.get(), f.geom, bad, dz);
    EXPECT_DOUBLE_EQ(dz[0], dz0);
    // a folded cell: node (1, 1, 1) lifted above node (1, 1, 2) on the flat stretched mesh. Its negative
    // spacing is skipped, so the region over columns 0 .. 2 still finds the other columns' bottom cell
    // (before, the negative minimum fell back to the nominal dz)
    for (amrex::MFIter mfi(*flat.znd, false); mfi.isValid(); ++mfi) {
        auto za = flat.znd->array(mfi);
        amrex::LoopOnCpu(amrex::grow(mfi.validbox(), 2), [&](int i, int j, int k) {
            if (i == 1 && j == 1 && k == 1) { za(i,j,k) = z2 + Real(1.0); }
        });
    }
    const std::vector<Real> fold{Real(0.5) * ms.dx(), Real(0.5) * ms.dy(), Real(0.0), Real(1.5) * ms.dx(), Real(1.5) * ms.dy(), ms.H};
    erf_actuator::min_cell_heights(flat.znd.get(), flat.geom, fold, dz);
    EXPECT_NEAR(dz[0], ms.z_node(0, 0, 1) - ms.z_node(0, 0, 0), tol);
    EXPECT_LT(dz[0], dz0 - Real(5.0));
}

// tip_cell_heights: each cell of the disk counts with the share of the tip speed that can cross it,
// sqrt(R^2 - d^2) / R for a cell whose nearest point is d from the hub height on a flat mesh, plus the
// slope G of its faces on a sloping one (at most sqrt(1 + G^2)). On a stretched column the short cells low
// in the disk count less than their height alone; the slack moves the hub height by up to that much; on a
// planar slope a cell low in the disk can limit through its slope; a zero radius keeps the nominal dz
TEST(ActuatorSampling, TheTipCellHeightWeighsEachCellByTheTipSpeedThatCrossesIt)
{
    MeshSpec ms; ms.max_grid = {{4, 5, 3}};   // flat, stretch 1.15: spacings 29.1 m at the ground to 77.5 m at the top
    Fields flat(ms, false);
    const Real dz0 = ms.H / ms.nz;
    const Real tol = (sizeof(Real) == 8) ? Real(1.0e-9) : Real(1.0e-4);
    // the reference, over one column (every column of the flat mesh is the same)
    auto brute = [&](Real zl, Real zh, Real zc, Real R, Real slack) {
        Real best = 1.0e30;
        for (int k = 0; k < ms.nz; ++k) {
            const Real z0 = ms.z_node(0, 0, k), z1 = ms.z_node(0, 0, k + 1);
            if (!(z1 > zl && z0 < zh)) { continue; }
            const Real gap = (zc < z0) ? z0 - zc : ((zc > z1) ? zc - z1 : Real(0.0));
            const Real d = std::max(gap - slack, Real(0.0));
            if (d >= R) { continue; }
            best = std::min(best, (z1 - z0) / (std::sqrt(R * R - d * d) / R));
        }
        return best;
    };
    const Real zc = 200.0, R = 120.0;
    const std::vector<Real> rows{100.0, 100.0, zc - R, 500.0, 500.0, zc + R, zc, R, 0.0};
    std::vector<Real> dz, plain;
    erf_actuator::tip_cell_heights(flat.znd.get(), flat.geom, rows, dz);
    ASSERT_EQ(dz.size(), 1u);
    EXPECT_NEAR(dz[0], brute(zc - R, zc + R, zc, R, Real(0.0)), tol);
    // hand values: the cell 145.5 .. 196.5 m (51.0 m, 3.5 m below the hub) gives 50.99 m; the one
    // 101.2 .. 145.5 m (44.3 m, 54.5 m below) gives 44.32 / 0.891 = 49.74 m, the limit
    EXPECT_NEAR(dz[0], Real(49.743), Real(0.005));
    const std::vector<Real> box(rows.begin(), rows.begin() + 6);
    erf_actuator::min_cell_heights(flat.znd.get(), flat.geom, box, plain);
    EXPECT_GT(dz[0], plain[0] + Real(10.0));   // the 38.5 m cell 99 m below the hub counts as 67.9 m
    // a slack of 60 m brings every cell 60 m nearer the hub height: the 38.5 m cell 98.8 m below now
    // counts as 38.54 / 0.946 = 40.73 m and is the limit
    const std::vector<Real> slack{100.0, 100.0, zc - R, 500.0, 500.0, zc + R, zc, R, 60.0};
    erf_actuator::tip_cell_heights(flat.znd.get(), flat.geom, slack, dz);
    EXPECT_NEAR(dz[0], brute(zc - R, zc + R, zc, R, Real(60.0)), tol);
    EXPECT_NEAR(dz[0], Real(40.727), Real(0.005));
    // a zero radius (no blades): the nominal dz
    const std::vector<Real> bare{100.0, 100.0, zc - R, 500.0, 500.0, zc + R, zc, 0.0, 0.0};
    erf_actuator::tip_cell_heights(flat.znd.get(), flat.geom, bare, dz);
    EXPECT_DOUBLE_EQ(dz[0], dz0);
    // a planar slope, ground h = 0.25 x under equal cells (z = h + (400 - h) k / 8): face k slopes as
    // 0.25 (1 - k / 8), so a tip moving sideways crosses it as well. The limit is the bottom cell of the
    // column x = 800 m (200 .. 225 m, 75 m below a hub at 300 m): 25 / (0.7806 + 0.25) = 24.257 m, where
    // the vertical speed alone (q) would give the 25 m of the cell at hub height
    MeshSpec mp = ms; mp.stretch = 1.0;
    Fields plane(mp, false);
    for (amrex::MFIter mfi(*plane.znd, false); mfi.isValid(); ++mfi) {
        auto za = plane.znd->array(mfi);
        amrex::LoopOnCpu(amrex::grow(mfi.validbox(), 2), [&](int i, int j, int k) {
            amrex::ignore_unused(j);
            const Real h = Real(0.25) * i * mp.dx();
            za(i,j,k) = h + (mp.H - h) * Real(k) / mp.nz;
        });
    }
    const std::vector<Real> prow{500.0, 300.0, 180.0, 700.0, 700.0, 420.0, 300.0, 120.0, 0.0};
    erf_actuator::tip_cell_heights(plane.znd.get(), plane.geom, prow, dz);
    EXPECT_NEAR(dz[0], Real(25.0) / (std::sqrt(Real(1.0) - Real(0.625) * Real(0.625)) + Real(0.25)), Real(1.0e-4));
    EXPECT_NEAR(dz[0], Real(24.2571), Real(1.0e-3));
    erf_actuator::min_cell_heights(plane.znd.get(), plane.geom, std::vector<Real>(prow.begin(), prow.begin() + 6), plain);
    EXPECT_NEAR(plain[0], Real(25.0), Real(1.0e-4));   // the plain vertical spacing is not weighted
    // a region at the domain's high x side (not periodic): the ghost nodes beyond it are not read, so a
    // fill value there (a fine level can leave one) changes nothing
    const std::vector<Real> side{1000.0, 300.0, 280.0, 1200.0, 700.0, 400.0, 340.0, 120.0, 0.0};
    std::vector<Real> clean;
    erf_actuator::tip_cell_heights(plane.znd.get(), plane.geom, side, clean);
    for (amrex::MFIter mfi(*plane.znd, false); mfi.isValid(); ++mfi) {
        auto za = plane.znd->array(mfi);
        amrex::LoopOnCpu(amrex::grow(mfi.validbox(), 2), [&](int i, int j, int k) {
            if (i < 0 || i > mp.nx) { za(i,j,k) = Real(1.0e30); }
        });
    }
    erf_actuator::tip_cell_heights(plane.znd.get(), plane.geom, side, dz);
    EXPECT_EQ(dz[0], clean[0]);
    EXPECT_GT(dz[0], Real(10.0));
}

// tip_cell_heights_batched: one reduction over every region gives each region the height the per-region
// search gives it, on a flat stretched mesh, over the hill, with periodic seams in x and y and boxes split
// in every direction, for regions empty, non-finite, without blades, straddling a seam or far outside, in
// any order and any subset (a cache searches only the rotors that moved)
TEST(ActuatorSampling, TheBatchedTipCellHeightsMatchThePerRegionSearch)
{
    // equal to the last bit on the host, where both take the same expression per cell; to rounding on a
    // device, which may contract the two kernels differently
    auto same = [](Real a, Real b) {
#ifdef AMREX_USE_GPU
        return a == b || std::abs(a - b) <= Real(8.0) * std::numeric_limits<Real>::epsilon() * std::max(std::abs(a), std::abs(b));
#else
        return a == b;
#endif
    };
    const Real nan = std::numeric_limits<Real>::quiet_NaN();
    for (const Real hill : {Real(0.0), Real(100.0)}) {
        for (const std::array<int,3>& periodic : {std::array<int,3>{{0, 0, 0}}, std::array<int,3>{{1, 1, 0}}}) {
            MeshSpec m; m.hill = hill; m.max_grid = {{4, 5, 3}};
            Fields f(m, false);
            const amrex::RealBox rb({AMREX_D_DECL(0.0, 0.0, 0.0)}, {AMREX_D_DECL(m.Lx, m.Ly, m.H)});
            const amrex::Geometry geom(f.geom.Domain(), &rb, 0, periodic.data());
            // the hand-picked regions, then a sweep of rotors over the domain and beyond its sides, with
            // tilted, yawed and coned shapes (box widths, slack) that differ from row to row
            std::vector<Real> rows{
                100.0, 100.0, 80.0, 500.0, 500.0, 320.0, 200.0, 120.0, 0.0,               // the middle
                -150.0, 400.0, 30.0, 90.0, 640.0, 270.0, 150.0, 120.0, 4.0,               // across x = 0
                1000.0, 850.0, 20.0, 1300.0, 1150.0, 260.0, 140.0, 120.0, 0.0,            // across both upper sides
                1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,                              // empty: no line
                nan, 100.0, 80.0, 500.0, 500.0, 320.0, 200.0, 120.0, 0.0,                 // a diverged hub
                100.0, 100.0, 80.0, 500.0, 500.0, 320.0, 200.0, 0.0, 0.0,                 // no blades
                -1.0e12, 100.0, 0.0, 1.0e12, 300.0, 400.0, 200.0, 120.0, 0.0,             // huge but finite
                5000.0, 5000.0, 80.0, 5200.0, 5200.0, 320.0, 200.0, 120.0, 0.0,           // far outside
                300.0, 200.0, 350.0, 900.0, 800.0, 500.0, 420.0, 120.0, 10.0};            // above the top
            for (int s = 0; s < 24; ++s) {
                const Real cx = Real(-200.0) + Real(70.0) * s, cy = Real(-150.0) + Real(53.0) * s;
                const Real cz = Real(120.0) + Real(7.0) * (s % 9), rad = Real(60.0) + Real(5.0) * (s % 7);
                const Real hx = rad * Real(0.1) * (s % 5), hy = rad * (Real(1.0) - Real(0.05) * (s % 3));
                rows.insert(rows.end(), {cx - hx, cy - hy, cz - rad, cx + hx, cy + hy, cz + rad, cz, rad, Real(0.5) * (s % 4)});
            }
            const int n = static_cast<int>(rows.size() / 9);
            std::vector<Real> one, batched;
            erf_actuator::tip_cell_heights(f.znd.get(), geom, rows, one);
            erf_actuator::tip_cell_heights_batched(f.znd.get(), geom, rows, batched);
            ASSERT_EQ(batched.size(), one.size());
            int limited = 0;   // regions whose height is a cell's, not the nominal dz
            for (int r = 0; r < n; ++r) {
                EXPECT_TRUE(same(batched[r], one[r])) << "hill " << hill << " periodic " << periodic[0] << " region " << r
                                                      << ": batched " << batched[r] << ", per region " << one[r];
                if (one[r] != m.H / m.nz) { ++limited; }
            }
            EXPECT_GT(limited, n / 2);
            // any subset, in any order: a region's height does not depend on the others searched with it
            std::vector<int> pick;
            for (int r = n - 1; r >= 0; r -= 3) { pick.push_back(r); }
            std::vector<Real> sub, part;
            for (const int r : pick) { sub.insert(sub.end(), rows.begin() + 9 * r, rows.begin() + 9 * r + 9); }
            erf_actuator::tip_cell_heights_batched(f.znd.get(), geom, sub, part);
            ASSERT_EQ(part.size(), pick.size());
            for (std::size_t k = 0; k < pick.size(); ++k) { EXPECT_TRUE(same(part[k], one[pick[k]])) << "region " << pick[k]; }
        }
    }
    // no regions, and a null z_phys_nd (the nominal dz), as for the per-region search
    MeshSpec m;
    Fields nominal(m, true);
    std::vector<Real> dz{1.0};
    erf_actuator::tip_cell_heights_batched(nominal.znd.get(), nominal.geom, std::vector<Real>{}, dz);
    EXPECT_TRUE(dz.empty());
    const std::vector<Real> row{100.0, 100.0, 80.0, 500.0, 500.0, 320.0, 200.0, 120.0, 0.0};
    erf_actuator::tip_cell_heights_batched(nominal.znd.get(), nominal.geom, row, dz);
    ASSERT_EQ(dz.size(), 1u);
    EXPECT_DOUBLE_EQ(dz[0], m.H / m.nz);
}
