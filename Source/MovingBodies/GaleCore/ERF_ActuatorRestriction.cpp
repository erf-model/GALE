#include "ERF_ActuatorRestriction.H"

#include <AMReX.H>
#include <AMReX_BLProfiler.H>
#include <AMReX_Gpu.H>
#include <AMReX_MFIter.H>

#include "ERF_ActuatorGeometry.H"

using namespace amrex;

namespace erf_actuator {

namespace {

void check_face_layout (int dir, const MultiFab& a, const MultiFab& b, const MultiFab* detJ_cc, const char* who)
{
    const IndexType face(IntVect::TheDimensionVector(dir));
    AMREX_ALWAYS_ASSERT_WITH_MESSAGE(dir >= 0 && dir <= 2 && a.ixType() == face && b.ixType() == face,
                                     std::string(who) + ": the fields must be face-centred in direction dir (0, 1 or 2)");
    AMREX_ALWAYS_ASSERT_WITH_MESSAGE(a.boxArray() == b.boxArray() && a.DistributionMap() == b.DistributionMap(),
                                     std::string(who) + ": the two fields must share boxes and distribution");
    AMREX_ALWAYS_ASSERT_WITH_MESSAGE(detJ_cc == nullptr ||
                                     (detJ_cc->nGrow() >= 1 && detJ_cc->DistributionMap() == a.DistributionMap() &&
                                      detJ_cc->boxArray() == amrex::convert(a.boxArray(), IntVect(0))),
                                     std::string(who) + ": detJ_cc must share the boxes and distribution and have one ghost cell");
}

} // namespace

void
source_to_face_forces (int dir, const MultiFab& src, const MultiFab* detJ_cc, const Geometry& geom, MultiFab& force)
{
    BL_PROFILE("erf_actuator::source_to_face_forces()");
    check_face_layout(dir, src, force, detJ_cc, "source_to_face_forces");
    const auto dx = geom.CellSizeArray();
    const Real dxdydz = dx[0] * dx[1] * dx[2];
    const bool has_detj = (detJ_cc != nullptr);
    for (MFIter mfi(force, TilingIfNotGPU()); mfi.isValid(); ++mfi) {
        const Box bx = mfi.tilebox();
        Array4<Real const> const& s = src.const_array(mfi);
        Array4<Real> const& f = force.array(mfi);
        Array4<Real const> detj = has_detj ? detJ_cc->const_array(mfi) : Array4<Real const>{};
        ParallelFor(bx, [=] AMREX_GPU_DEVICE (int i, int j, int k) noexcept
        {
            f(i,j,k) = s(i,j,k) * face_volume(dir, i, j, k, detj, has_detj, dxdydz);
        });
    }
}

void
face_forces_to_source (int dir, const MultiFab& force, const MultiFab* detJ_cc, const Geometry& geom, MultiFab& src)
{
    BL_PROFILE("erf_actuator::face_forces_to_source()");
    check_face_layout(dir, force, src, detJ_cc, "face_forces_to_source");
    const auto dx = geom.CellSizeArray();
    const Real dxdydz = dx[0] * dx[1] * dx[2];
    const bool has_detj = (detJ_cc != nullptr);
    for (MFIter mfi(src, TilingIfNotGPU()); mfi.isValid(); ++mfi) {
        const Box bx = mfi.tilebox();
        Array4<Real const> const& f = force.const_array(mfi);
        Array4<Real> const& s = src.array(mfi);
        Array4<Real const> detj = has_detj ? detJ_cc->const_array(mfi) : Array4<Real const>{};
        ParallelFor(bx, [=] AMREX_GPU_DEVICE (int i, int j, int k) noexcept
        {
            s(i,j,k) = f(i,j,k) / face_volume(dir, i, j, k, detj, has_detj, dxdydz);
        });
    }
}

void
restrict_face_forces (int dir, const MultiFab& fine, const Geometry& fine_geom, const IntVect& ratio, MultiFab& crse)
{
    BL_PROFILE("erf_actuator::restrict_face_forces()");
    const IntVect fdir = IntVect::TheDimensionVector(dir);
    AMREX_ALWAYS_ASSERT_WITH_MESSAGE(dir >= 0 && dir <= 2 && fine.ixType() == IndexType(fdir) && crse.ixType() == IndexType(fdir),
                                     "restrict_face_forces: the fields must be face-centred in direction dir (0, 1 or 2)");
    AMREX_ALWAYS_ASSERT_WITH_MESSAGE(ratio.allGE(IntVect(1)), "restrict_face_forces: the refinement ratio must be at least 1");

    // the fine faces on boxes that coarsen exactly (each fine box grown to the next coarse cells when
    // it does not: the grown boxes may overlap, and every copy of a face then takes the same value),
    // with the r - 1 faces beyond each box's ends in direction dir that the coarse faces on its ends
    // reach (filled from the neighbouring boxes; zero where no fine box is)
    const int rn = ratio[dir];
    const int reach = rn - 1;
    BoxArray cells = amrex::convert(fine.boxArray(), IntVect(0));
    if (!cells.coarsenable(ratio)) { cells.coarsen(ratio).refine(ratio); }
    const DistributionMapping& dm = fine.DistributionMap();
    IntVect ng(0);
    ng[dir] = reach;
    MultiFab work(amrex::convert(cells, fdir), dm, 1, ng);
    work.setVal(0.0);
    work.ParallelCopy(fine, 0, 0, 1, IntVect(0), IntVect(0));
    work.FillBoundary(fine_geom.periodicity());

    // the coarse faces of those boxes: each the weighted sum over its control volume
    MultiFab sum(amrex::convert(amrex::coarsen(cells, ratio), fdir), dm, 1, 0);
    const int r0 = ratio[0], r1 = ratio[1], r2 = ratio[2];
    const int off_lo = -reach;
    const int na = 2 * reach + 1;
    const Real inv_rn = Real(1.0) / static_cast<Real>(rn);
    for (MFIter mfi(sum, TilingIfNotGPU()); mfi.isValid(); ++mfi) {
        const Box bx = mfi.tilebox();
        Array4<Real const> const& f = work.const_array(mfi);
        Array4<Real> const& c = sum.array(mfi);
        ParallelFor(bx, [=] AMREX_GPU_DEVICE (int I, int J, int K) noexcept
        {
            const int lo[3] = {r0 * I + ((dir == 0) ? off_lo : 0),
                               r1 * J + ((dir == 1) ? off_lo : 0),
                               r2 * K + ((dir == 2) ? off_lo : 0)};
            const int n[3] = {(dir == 0) ? na : r0, (dir == 1) ? na : r1, (dir == 2) ? na : r2};
            Real acc = Real(0.0);
            for (int kk = 0; kk < n[2]; ++kk) {
                for (int jj = 0; jj < n[1]; ++jj) {
                    for (int ii = 0; ii < n[0]; ++ii) {
                        // the linear (cloud-in-cell) weight of a fine face |off| fine faces from the coarse face
                        int off = ((dir == 0) ? ii : ((dir == 1) ? jj : kk)) - reach;
                        if (off < 0) { off = -off; }
                        const Real w = Real(1.0) - static_cast<Real>(off) * inv_rn;
                        acc += w * f(lo[0] + ii, lo[1] + jj, lo[2] + kk);
                    }
                }
            }
            c(I,J,K) = acc;
        });
    }

    // onto the coarse level's boxes; a face on the end of two summed boxes carries the same value in both
    crse.setVal(0.0);
    crse.ParallelCopy(sum, 0, 0, 1, IntVect(0), IntVect(0));
}

} // namespace erf_actuator
