// Contract of erf_actuator::face_forces_to_source, which converts the face forces of an earlier
// version's checkpoint (moving_bodies/force_x, _y, _z) into the bodies' source: on each face,
// src_f = F_f / dV_f with dV_f = dx dy dz on a uniform mesh and dx dy dz (J_{m-1} + J_m) / 2 with
// the two cells beside the face on a terrain-following mesh, in every direction and on a level
// split into boxes (the low neighbour of a box's first face is its ghost cell).

#include <array>
#include <cmath>

#include <AMReX_Box.H>
#include <AMReX_BoxArray.H>
#include <AMReX_DistributionMapping.H>
#include <AMReX_Geometry.H>
#include <AMReX_MultiFab.H>
#include <AMReX_RealBox.H>

#include <gtest/gtest.h>

#include "ERF_ActuatorRestriction.H"

namespace {

using amrex::Real;
using amrex::IntVect;

constexpr int NX = 8, NY = 6, NZ = 5;
constexpr Real Lx = 800.0, Ly = 300.0, H = 200.0;   // cells 100 m x 50 m x 40 m

Real jac (int i, int j, int k) { return 0.7 + 0.05 * i + 0.03 * j * j + 0.02 * k; }
Real force (int d, int i, int j, int k) { return 1.0e4 * (d + 1) - 37.0 * i + 11.0 * j - 5.0 * k * k; }

void check (bool terrain)
{
    const amrex::Box domain(IntVect(0), IntVect(NX - 1, NY - 1, NZ - 1));
    const amrex::RealBox rb({AMREX_D_DECL(0.0, 0.0, 0.0)}, {AMREX_D_DECL(Lx, Ly, H)});
    const int per[3] = {1, 1, 0};
    const amrex::Geometry geom(domain, &rb, 0, per);
    amrex::BoxArray ba(domain);
    ba.maxSize(IntVect(4, 3, 2));
    const amrex::DistributionMapping dm(ba);
    const Real dxdydz = (Lx / NX) * (Ly / NY) * (H / NZ);

    amrex::MultiFab detj(ba, dm, 1, 1);
    for (amrex::MFIter mfi(detj, false); mfi.isValid(); ++mfi) {
        const auto a = detj.array(mfi);
        amrex::LoopOnCpu(mfi.growntilebox(), [&] (int i, int j, int k) { a(i,j,k) = jac(i, j, k); });
    }
    for (int d = 0; d < 3; ++d) {
        const amrex::BoxArray fba = amrex::convert(ba, IntVect::TheDimensionVector(d));
        amrex::MultiFab f(fba, dm, 1, 0), src(fba, dm, 1, 0);
        for (amrex::MFIter mfi(f, false); mfi.isValid(); ++mfi) {
            const auto a = f.array(mfi);
            amrex::LoopOnCpu(mfi.validbox(), [&] (int i, int j, int k) { a(i,j,k) = force(d, i, j, k); });
        }
        src.setVal(-1.0);
        erf_actuator::face_forces_to_source(d, f, terrain ? &detj : nullptr, geom, src);
        const IntVect e = IntVect::TheDimensionVector(d);
        int n = 0;
        for (amrex::MFIter mfi(src, false); mfi.isValid(); ++mfi) {
            const auto s = src.const_array(mfi);
            amrex::LoopOnCpu(mfi.validbox(), [&] (int i, int j, int k) {
                const Real dv = terrain ? 0.5 * (jac(i - e[0], j - e[1], k - e[2]) + jac(i, j, k)) * dxdydz : dxdydz;
                const Real expect = force(d, i, j, k) / dv;
                EXPECT_NEAR(s(i,j,k), expect, 1.e-13 * std::abs(expect))
                    << "direction " << d << " face (" << i << "," << j << "," << k << ")"
                    << (terrain ? " with detJ" : " without detJ");
                ++n;
            });
        }
        EXPECT_EQ(n, static_cast<int>(fba.numPts())) << "every face is converted, direction " << d;
    }
}

} // namespace

TEST (ActuatorRestriction, FaceForcesToSourceOnAUniformMesh) { check(false); }

TEST (ActuatorRestriction, FaceForcesToSourceOnATerrainFollowingMesh) { check(true); }
