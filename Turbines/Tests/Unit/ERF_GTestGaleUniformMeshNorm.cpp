// GALE's test of uniform_mesh_norm (GaleCore/ERF_UniformMeshNorm): the normalisation one rank finds alone on a
// uniform mesh is the sum of the ranks' partial norms. Moved here from ERF_GTestActuatorSpreading.cpp,
// unchanged; the helpers Mesh and Sources are copies of the ones there.

#include <AMReX_ParallelReduce.H>
#include "ERF_ActuatorGeometry.H"
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <memory>
#include <vector>

#include <AMReX_Box.H>
#include <AMReX_BoxArray.H>
#include <AMReX_DistributionMapping.H>
#include <AMReX_Geometry.H>
#include <AMReX_MultiFab.H>
#include <AMReX_ParallelDescriptor.H>
#include <AMReX_RealBox.H>

#include <gtest/gtest.h>

#include "ERF_ActuatorSpreading.H"
#include "ERF_UniformMeshNorm.H"
#include "ERF_GTestThrowOnAbort.H"

namespace {

using amrex::Real;

struct Mesh {
    int nx = 24, ny = 12, nz = 10;
    Real Lx = 2400.0, Ly = 1200.0, H = 500.0;
    Real hill = 0.0;                       // basic terrain-following (BTF) terrain amplitude (m); 0: flat
    std::array<int,3> max_grid{{1024, 1024, 1024}};
    std::array<int,3> periodic{{1, 1, 0}};

    Real dx () const { return Lx / nx; }
    Real dy () const { return Ly / ny; }
    Real h (Real x, Real y) const
    {
        constexpr Real pi = 3.14159265358979323846;
        return hill * (0.5 + 0.5 * std::cos(2.0 * pi * x / Lx)) * (0.5 + 0.5 * std::sin(2.0 * pi * y / Ly));
    }
    // the horizontal spacings, divided once for the loops that fill or read a field. Called inside those loops,
    // dx() and dy() let clang -O2 divide two-lane vectors with an unused lane: {Lx, 0} / {nx, 0} and
    // {Ly, H} / {ny, 0}. The unused lanes' 0 / 0 and H / 0 are discarded, but they raise the flags that
    // amrex.fpe_trap_invalid and fpe_trap_zero stop on
    struct Spacing { Real dx, dy; };
    Spacing spacing () const { return {dx(), dy()}; }
    // basic terrain-following (BTF) with uniform nominal levels: the Jacobian of a column is (H - h) / H
    Real z_node (const Spacing& s, int i, int j, int k) const
    {
        const Real hs = h(i * s.dx, j * s.dy);
        return hs + (H - hs) * k / nz;
    }
    Real detj (const Spacing& s, int i, int j) const { return (H - h((i + 0.5) * s.dx, (j + 0.5) * s.dy)) / H; }
};

struct Sources {
    amrex::Geometry geom;
    amrex::BoxArray ba;
    amrex::DistributionMapping dm;
    amrex::MultiFab sx, sy, sz;
    std::unique_ptr<amrex::MultiFab> znd, detj;
    Mesh mesh;

    // dm_in: the distribution of another Sources on the same mesh, to compare the two box by box
    Sources (const Mesh& m, bool terrain, const amrex::DistributionMapping* dm_in = nullptr)
        : mesh(m)
    {
        const amrex::Box domain(amrex::IntVect(0, 0, 0), amrex::IntVect(m.nx-1, m.ny-1, m.nz-1));
        const amrex::RealBox rb({AMREX_D_DECL(0.0, 0.0, 0.0)}, {AMREX_D_DECL(m.Lx, m.Ly, m.H)});
        geom = amrex::Geometry(domain, &rb, 0, m.periodic.data());
        ba = amrex::BoxArray(domain);
        ba.maxSize(amrex::IntVect(m.max_grid[0], m.max_grid[1], m.max_grid[2]));
        dm = (dm_in != nullptr) ? *dm_in : amrex::DistributionMapping(ba);
        sx.define(amrex::convert(ba, amrex::IntVect(1,0,0)), dm, 1, 0);
        sy.define(amrex::convert(ba, amrex::IntVect(0,1,0)), dm, 1, 0);
        sz.define(amrex::convert(ba, amrex::IntVect(0,0,1)), dm, 1, 0);
        if (terrain) {
            const int ng = 1;
            znd = std::make_unique<amrex::MultiFab>(amrex::convert(ba, amrex::IntVect(1,1,1)), dm, 1, ng);
            detj = std::make_unique<amrex::MultiFab>(ba, dm, 1, ng);
            const Mesh::Spacing sp = m.spacing();
            for (amrex::MFIter mfi(*detj, false); mfi.isValid(); ++mfi) {
                auto za = znd->array(mfi);
                auto ja = detj->array(mfi);
                const amrex::Box gbx = amrex::grow(mfi.validbox(), ng);
                amrex::LoopOnCpu(amrex::surroundingNodes(gbx),
                                 [&](int i, int j, int k) { za(i,j,k) = m.z_node(sp, i, j, k); });
                amrex::LoopOnCpu(gbx, [&](int i, int j, int k) { ja(i,j,k) = m.detj(sp, i, j); (void) k; });
            }
        }
    }
};

} // namespace

TEST(ActuatorSpreading, UniformMeshNormIsTheSummedNorm)
{
    // the normalisation one rank finds alone on a uniform mesh is the one the ranks' partial sums add up
    // to, to 1e-12 relative: inside, across the periodic seams in x, in y and at their corner, cut by the
    // ground and by the top, on box faces, and for a kernel wider than the domain in y (several images)
    Mesh m;
    m.max_grid = {{8, 8, 4}};   // several boxes, so the partial sums come from several of them (and ranks)
    Sources s(m, false);
    const Real dx = m.dx(), dz = m.H / m.nz;
    std::vector<Real> pos, eps;
    auto add = [&] (Real x, Real y, Real z, Real e) { pos.insert(pos.end(), {x, y, z}); eps.push_back(e); };
    add(Real(0.37) * m.Lx, Real(0.41) * m.Ly, Real(0.5) * m.H, Real(2.0) * dx);           // inside
    add(Real(0.1) * dx, Real(0.5) * m.Ly, Real(0.5) * m.H, Real(2.0) * dx);               // x seam
    add(Real(0.5) * m.Lx, m.Ly - Real(0.2) * m.dy(), Real(0.5) * m.H, Real(1.5) * dx);    // y seam
    add(m.Lx - Real(0.3) * dx, Real(0.05) * m.dy(), Real(0.45) * m.H, Real(2.5) * dx);    // corner
    add(Real(0.6) * m.Lx, Real(0.3) * m.Ly, Real(0.3) * dz, Real(2.0) * dx);              // ground
    add(Real(0.2) * m.Lx, Real(0.7) * m.Ly, m.H - Real(0.4) * dz, Real(1.0) * dx);        // top
    add(Real(8.0) * dx, Real(4.0) * m.dy(), Real(4.0) * dz, Real(2.0) * dx);              // on box faces
    add(Real(0.5) * m.Lx, Real(0.5) * m.Ly, Real(0.5) * m.H, Real(0.6) * m.Ly);           // wider than y
    std::vector<Real> summed;
    erf_actuator::spread_partial_norms(pos, eps, nullptr, nullptr, s.geom, s.sx, summed);
    amrex::ParallelDescriptor::ReduceRealSum(summed.data(), static_cast<int>(summed.size()));
    for (std::size_t p = 0; p < eps.size(); ++p) {
        Real local[3] = {Real(-1.0), Real(-1.0), Real(-1.0)};
        ASSERT_TRUE(erf_actuator::uniform_mesh_norm(pos[3*p], pos[3*p+1], pos[3*p+2], eps[p], s.geom, s.ba, local)) << "point " << p;
        for (int d = 0; d < 3; ++d) {
            ASSERT_GT(summed[3*p+d], Real(0.0));
            const Real tol = (sizeof(Real) == 8) ? Real(1.0e-12) : Real(1.0e-5);
            EXPECT_LE(std::abs(local[d] - summed[3*p+d]), tol * summed[3*p+d]) << "point " << p << " component " << d;
        }
    }
    // a refined level that does not cover a kernel's reach: no local normalisation (the faces outside its
    // boxes get no source), and the norm is left alone
    amrex::BoxArray part(amrex::Box(amrex::IntVect(0, 0, 0), amrex::IntVect(m.nx / 2 - 1, m.ny - 1, m.nz - 1)));
    Real untouched[3] = {Real(7.0), Real(7.0), Real(7.0)};
    EXPECT_FALSE(erf_actuator::uniform_mesh_norm(Real(0.5) * m.Lx, Real(0.5) * m.Ly, Real(0.5) * m.H, Real(2.0) * dx, s.geom, part,
                                                 untouched));
    EXPECT_EQ(untouched[0], Real(7.0));
    // but a kernel well inside its boxes is
    EXPECT_TRUE(erf_actuator::uniform_mesh_norm(Real(0.2) * m.Lx, Real(0.5) * m.Ly, Real(0.5) * m.H, Real(1.0) * dx, s.geom, part,
                                                untouched));
}
