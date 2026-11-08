// Contract of erf_actuator::restrict_face_forces (with source_to_face_forces and face_forces_to_source):
// a source spread on a refined patch gives each coarser level a source that integrates to the same
// force on every component, for even and odd refinement ratios, with a kernel of one fine cell (1/r of a
// coarse cell), when the fine boxes are split (shared faces counted once) or do not coarsen exactly,
// and on a terrain-following mesh with its cell volumes; a fine face on a coarse control volume's end
// gives half its force to each of the two coarse faces, one on a coarse face all of it, and for r = 4
// the linear weights 3/4 and 1/4; the force's centroid in each face's own direction is kept; a patch
// across a periodic seam and an anisotropic ratio conserve the force; the result does not depend on
// how the fine boxes are split.

#include <array>
#include <cmath>
#include <memory>
#include <vector>

#include <AMReX_Box.H>
#include <AMReX_BoxArray.H>
#include <AMReX_DistributionMapping.H>
#include <AMReX_Geometry.H>
#include <AMReX_MultiFab.H>
#include <AMReX_RealBox.H>

#include <gtest/gtest.h>

#include "ERF_ActuatorRestriction.H"
#include "ERF_ActuatorSpreading.H"

namespace {

using amrex::Real;
using amrex::IntVect;

constexpr Real Lx = 1600.0, Ly = 800.0, H = 640.0;
constexpr int NX = 40, NY = 20, NZ = 16;    // coarse cells: 40 m

amrex::Geometry make_geom (const IntVect& r)
{
    const amrex::Box domain(IntVect(0), IntVect(NX * r[0] - 1, NY * r[1] - 1, NZ * r[2] - 1));
    const amrex::RealBox rb({AMREX_D_DECL(0.0, 0.0, 0.0)}, {AMREX_D_DECL(Lx, Ly, H)});
    const int per[3] = {1, 1, 0};
    return amrex::Geometry(domain, &rb, 0, per);
}

// a level: its boxes (cell-centred), the three face fields and, on a terrain-following mesh, detJ
struct Level {
    amrex::Geometry geom;
    amrex::BoxArray ba;
    amrex::DistributionMapping dm;
    std::array<amrex::MultiFab, 3> f;
    std::unique_ptr<amrex::MultiFab> detj;

    Level (const IntVect& r, const amrex::Box& cells, int max_grid, bool terrain)
        : geom(make_geom(r)), ba(cells)
    {
        ba.maxSize(max_grid);
        dm = amrex::DistributionMapping(ba);
        for (int d = 0; d < 3; ++d) { f[d].define(amrex::convert(ba, IntVect::TheDimensionVector(d)), dm, 1, 0); f[d].setVal(0.0); }
        if (terrain) {
            detj = std::make_unique<amrex::MultiFab>(ba, dm, 1, 1);
            const Real dx = geom.CellSize(0);
            for (amrex::MFIter mfi(*detj, false); mfi.isValid(); ++mfi) {
                const auto a = detj->array(mfi);
                amrex::LoopOnCpu(mfi.growntilebox(), [&] (int i, int j, int k) {
                    a(i,j,k) = 0.8 + 0.2 * std::cos(2.0 * 3.14159265358979 * (i + 0.5) * dx / Lx) + 0.01 * k;
                });
            }
        }
    }
};

// spread one point force on the fine level, restrict to the coarse level, return the forces both integrate to
std::array<std::array<Real,2>,3> restrict_point (Level& fine, Level& crse, const IntVect& r, Real eps,
                                                 const std::vector<Real>& pos = {612.3, 401.7, 318.9})
{
    const std::vector<Real> force = {-7.0e5, 1.3e4, -5.5e4};
    erf_actuator::spread_forces(pos, force, eps, nullptr, fine.detj.get(), fine.geom, fine.f[0], fine.f[1], fine.f[2]);
    std::array<std::array<Real,2>,3> total{};
    for (int d = 0; d < 3; ++d) {
        amrex::MultiFab ff(fine.f[d].boxArray(), fine.dm, 1, 0), fc(crse.f[d].boxArray(), crse.dm, 1, 0);
        erf_actuator::source_to_face_forces(d, fine.f[d], fine.detj.get(), fine.geom, ff);
        erf_actuator::restrict_face_forces(d, ff, fine.geom, r, fc);
        erf_actuator::face_forces_to_source(d, fc, crse.detj.get(), crse.geom, crse.f[d]);
        total[d][0] = erf_actuator::integrate_source(d, fine.f[d], fine.detj.get(), fine.geom);
        total[d][1] = erf_actuator::integrate_source(d, crse.f[d], crse.detj.get(), crse.geom);
        EXPECT_NEAR(total[d][0], force[d], 1.e-9 * std::abs(force[0])) << "fine spread, component " << d;
    }
    return total;
}

// the patch: x 480..800, y 320..480, z 240..400 m on the coarse grid (cells 12..19, 8..11, 6..9)
amrex::Box patch (const IntVect& r) { return amrex::Box(IntVect(12, 8, 6), IntVect(19, 11, 9)).refine(r); }
amrex::Box coarse_domain () { return amrex::Box(IntVect(0), IntVect(NX - 1, NY - 1, NZ - 1)); }

} // namespace

TEST (ActuatorRestriction, ConservesTheForceForEvenRatios)
{
    for (int r : {2, 4, 8}) {
        Level fine(IntVect(r), patch(IntVect(r)), 8, false), crse(IntVect(1), coarse_domain(), 16, false);
        const auto t = restrict_point(fine, crse, IntVect(r), Real(40.0) / r);   // one fine cell: 1/r of a coarse cell
        for (int d = 0; d < 3; ++d) {
            EXPECT_NEAR(t[d][1], t[d][0], 1.e-10 * std::abs(t[0][0])) << "ratio " << r << ", component " << d;
        }
    }
}

TEST (ActuatorRestriction, ConservesTheForceForOddRatios)
{
    Level fine(IntVect(3), patch(IntVect(3)), 6, false), crse(IntVect(1), coarse_domain(), 16, false);
    const auto t = restrict_point(fine, crse, IntVect(3), Real(40.0) / 3);
    for (int d = 0; d < 3; ++d) { EXPECT_NEAR(t[d][1], t[d][0], 1.e-10 * std::abs(t[0][0])) << "component " << d; }
}

TEST (ActuatorRestriction, ConservesTheForceOnATerrainFollowingMesh)
{
    Level fine(IntVect(2), patch(IntVect(2)), 8, true), crse(IntVect(1), coarse_domain(), 16, true);
    const auto t = restrict_point(fine, crse, IntVect(2), Real(20.0));
    for (int d = 0; d < 3; ++d) { EXPECT_NEAR(t[d][1], t[d][0], 1.e-10 * std::abs(t[0][0])) << "component " << d; }
}

TEST (ActuatorRestriction, ConservesTheForceWhenTheFineBoxesDoNotCoarsen)
{
    // a patch shifted by one fine cell: its boxes do not coarsen by 2
    const amrex::Box p = amrex::Box(patch(IntVect(2))).shift(IntVect(1, 1, 1));
    Level fine(IntVect(2), p, 7, false), crse(IntVect(1), coarse_domain(), 16, false);
    const auto t = restrict_point(fine, crse, IntVect(2), Real(20.0));
    for (int d = 0; d < 3; ++d) { EXPECT_NEAR(t[d][1], t[d][0], 1.e-10 * std::abs(t[0][0])) << "component " << d; }
}

TEST (ActuatorRestriction, DoesNotDependOnTheFineBoxes)
{
    // the same fine source on two box layouts (spread once, copied: the spread's own sums follow the
    // boxes), restricted to the same coarse level, must give the same coarse source bit for bit
    Level fa(IntVect(2), patch(IntVect(2)), 4, false), fb(IntVect(2), patch(IntVect(2)), 64, false);
    Level ca(IntVect(1), coarse_domain(), 16, false), cb(IntVect(1), coarse_domain(), 16, false);
    restrict_point(fa, ca, IntVect(2), Real(20.0));
    for (int d = 0; d < 3; ++d) {
        fb.f[d].ParallelCopy(fa.f[d], 0, 0, 1);
        amrex::MultiFab ff(fb.f[d].boxArray(), fb.dm, 1, 0), fc(cb.f[d].boxArray(), cb.dm, 1, 0);
        erf_actuator::source_to_face_forces(d, fb.f[d], nullptr, fb.geom, ff);
        erf_actuator::restrict_face_forces(d, ff, fb.geom, IntVect(2), fc);
        erf_actuator::face_forces_to_source(d, fc, nullptr, cb.geom, cb.f[d]);
    }
    for (int d = 0; d < 3; ++d) {
        amrex::MultiFab diff(ca.f[d].boxArray(), ca.dm, 1, 0);
        amrex::MultiFab::Copy(diff, ca.f[d], 0, 0, 1, 0);
        amrex::MultiFab::Subtract(diff, cb.f[d], 0, 0, 1, 0);
        EXPECT_EQ(diff.norminf(0, 0), 0.0) << "component " << d;
        EXPECT_GT(ca.f[d].norminf(0, 0), 0.0) << "component " << d;
    }
}

TEST (ActuatorRestriction, SplitsAFaceOnAControlVolumeEndInHalves)
{
    // one fine x-face with 1 N at fine i = 25 (between coarse faces 12 and 13 for r = 2: half each)
    // and one at fine i = 28 (coarse face 14: all of it)
    Level fine(IntVect(2), patch(IntVect(2)), 8, false), crse(IntVect(1), coarse_domain(), 16, false);
    amrex::MultiFab ff(fine.f[0].boxArray(), fine.dm, 1, 0), fc(crse.f[0].boxArray(), crse.dm, 1, 0);
    ff.setVal(0.0);
    for (amrex::MFIter mfi(ff, false); mfi.isValid(); ++mfi) {
        const auto a = ff.array(mfi);
        const amrex::Box b = mfi.validbox();
        for (const IntVect& iv : {IntVect(25, 17, 13), IntVect(28, 17, 13)}) {
            if (b.contains(iv)) { a(iv) = 1.0; }
        }
    }
    erf_actuator::restrict_face_forces(0, ff, fine.geom, IntVect(2), fc);
    auto value = [&fc] (const IntVect& iv) {
        Real v = 0.0;
        for (amrex::MFIter mfi(fc, false); mfi.isValid(); ++mfi) { if (mfi.validbox().contains(iv)) { v = fc.const_array(mfi)(iv); } }
        amrex::ParallelDescriptor::ReduceRealMax(v);
        return v;
    };
    EXPECT_EQ(value(IntVect(12, 8, 6)), 0.5);
    EXPECT_EQ(value(IntVect(13, 8, 6)), 0.5);
    EXPECT_EQ(value(IntVect(14, 8, 6)), 1.0);
    EXPECT_EQ(value(IntVect(15, 8, 6)), 0.0);
}

TEST (ActuatorRestriction, UsesLinearWeightsAndKeepsTheCentroid)
{
    // r = 4: a fine x-face one fine face past coarse face 13 (fine i = 53) gives 3/4 to face 13 and 1/4 to face 14
    Level fine(IntVect(4), patch(IntVect(4)), 16, false), crse(IntVect(1), coarse_domain(), 16, false);
    amrex::MultiFab ff(fine.f[0].boxArray(), fine.dm, 1, 0), fc(crse.f[0].boxArray(), crse.dm, 1, 0);
    ff.setVal(0.0);
    for (amrex::MFIter mfi(ff, false); mfi.isValid(); ++mfi) {
        if (mfi.validbox().contains(IntVect(53, 34, 26))) { ff.array(mfi)(IntVect(53, 34, 26)) = 1.0; }
    }
    erf_actuator::restrict_face_forces(0, ff, fine.geom, IntVect(4), fc);
    Real v13 = 0.0, v14 = 0.0;
    for (amrex::MFIter mfi(fc, false); mfi.isValid(); ++mfi) {
        const auto a = fc.const_array(mfi);
        if (mfi.validbox().contains(IntVect(13, 8, 6))) { v13 = a(13, 8, 6); }
        if (mfi.validbox().contains(IntVect(14, 8, 6))) { v14 = a(14, 8, 6); }
    }
    amrex::ParallelDescriptor::ReduceRealMax(v13);
    amrex::ParallelDescriptor::ReduceRealMax(v14);
    EXPECT_DOUBLE_EQ(v13, 0.75);
    EXPECT_DOUBLE_EQ(v14, 0.25);

    // a narrow spread source: its x-force centroid along x is the same on both levels
    Level f2(IntVect(4), patch(IntVect(4)), 16, false), c2(IntVect(1), coarse_domain(), 16, false);
    restrict_point(f2, c2, IntVect(4), Real(10.0), {613.7, 401.7, 318.9});
    auto centroid = [] (const Level& L) {
        const Real dx = L.geom.CellSize(0), vol = dx * L.geom.CellSize(1) * L.geom.CellSize(2);
        Real m0 = 0.0, m1 = 0.0;
        for (amrex::MFIter mfi(L.f[0], false); mfi.isValid(); ++mfi) {
            const auto a = L.f[0].const_array(mfi);
            amrex::Box b = mfi.validbox();
            b.growHi(0, -1);   // each x-face once
            amrex::LoopOnCpu(b, [&] (int i, int j, int k) { m0 += a(i,j,k) * vol; m1 += a(i,j,k) * vol * i * dx; });
        }
        amrex::ParallelDescriptor::ReduceRealSum(m0);
        amrex::ParallelDescriptor::ReduceRealSum(m1);
        return m1 / m0;
    };
    EXPECT_NEAR(centroid(c2), centroid(f2), 1.e-8) << "x-force centroid (m)";
}

TEST (ActuatorRestriction, ConservesTheForceAcrossAPeriodicSeam)
{
    // a patch across x = 0 / Lx in two boxes, the point on the seam
    amrex::BoxList bl;
    bl.push_back(amrex::Box(IntVect(0, 16, 12), IntVect(15, 23, 19)));
    bl.push_back(amrex::Box(IntVect(2 * NX - 16, 16, 12), IntVect(2 * NX - 1, 23, 19)));
    Level fine(IntVect(2), amrex::Box(IntVect(0), IntVect(1)), 64, false), crse(IntVect(1), coarse_domain(), 16, false);
    fine.ba = amrex::BoxArray(bl);
    fine.dm = amrex::DistributionMapping(fine.ba);
    for (int d = 0; d < 3; ++d) { fine.f[d].define(amrex::convert(fine.ba, IntVect::TheDimensionVector(d)), fine.dm, 1, 0); fine.f[d].setVal(0.0); }
    const auto t = restrict_point(fine, crse, IntVect(2), Real(20.0), {1.3, 401.7, 318.9});
    for (int d = 0; d < 3; ++d) { EXPECT_NEAR(t[d][1], t[d][0], 1.e-10 * std::abs(t[0][0])) << "component " << d; }
}

TEST (ActuatorRestriction, ConservesTheForceForAnAnisotropicRatio)
{
    const IntVect r(2, 2, 1);
    Level fine(r, patch(r), 8, false), crse(IntVect(1), coarse_domain(), 16, false);
    const auto t = restrict_point(fine, crse, r, Real(20.0));   // the reach (60 m) inside the patch
    for (int d = 0; d < 3; ++d) { EXPECT_NEAR(t[d][1], t[d][0], 1.e-10 * std::abs(t[0][0])) << "component " << d; }
}
