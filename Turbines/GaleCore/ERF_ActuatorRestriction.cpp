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

} // namespace erf_actuator
