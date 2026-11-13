/**
 * @file ERF_GaleTurbineModel.cpp
 * @brief GALE's moving bodies (OpenFAST turbines and prescribed-Ct disks) as ERF's structure model "gale"
 *
 * erf.structures.model = gale selects it; the bodies keep their own inputs under erf.moving_bodies.*.
 * The model owns one MovingBodies and hands it what ERF gives every structure model
 * (ERF_StructureModel.H). ERF does the rest: it restricts the anchor level's source onto the coarser
 * levels (ERF::make_structure_coarse_sources), writes that source to <chk>/StructureCoarseSource, and
 * stops the run when a finer level covers support().
 */
#include "ERF_StructureModel.H"
#include "ERF_StructureModelRegistry.H"
#include "ERF_MovingBodies.H"
#include "ERF_MovingBodiesInputs.H"
#include "ERF_DataStruct.H"

#include <AMReX_ParmParse.H>
#include <AMReX_Utility.H>
#include <AMReX_VisMF.H>

#include <fstream>

using namespace amrex;

namespace {

class GaleTurbineModel final : public StructureModel
{
public:
    explicit GaleTurbineModel (int max_level)
        : m_in(MovingBodiesInputs::read()), m_max_level(max_level)
    {
        if (!m_in.active) {
            Abort("erf.structures.model = gale: no bodies are given; list them in erf.moving_bodies.bodies");
        }
        // with EB terrain ERF hands the model no heights and no Jacobian (a uniform-dz mesh), while the
        // bodies would need the plane offset and the cut-cell volumes; refused rather than run on flat ones
        TerrainType terrain = TerrainType::None;
        ParmParse("erf").query_enum_case_insensitive("terrain_type", terrain);
        if (terrain == TerrainType::EB) {
            Abort("erf.structures.model = gale does not run with erf.terrain_type = EB; use StaticFittedMesh or ImmersedForcing terrain");
        }
        m_anchor = MovingBodiesInputs::resolve_anchor_level(m_in.anchor_level, max_level);
        // the anchor level is checked now, as level() is asked for before initialize(); the other
        // solver checks of MovingBodies::create follow there
        const std::string err = MovingBodiesInputs::validate_solver(true, true, max_level, m_anchor, false);
        if (!err.empty()) { Abort(err); }
    }

    const char* name () const override { return "gale"; }

    int level (int finest_level) const override
    {
        if (m_anchor > finest_level) {
            if (!m_bodies) {
                Abort("erf.moving_bodies: the bodies live on level " + std::to_string(m_anchor) + " (erf.moving_bodies.anchor_level, "
                      "or amr.max_level when it is not given), but the run starts with levels 0 to " + std::to_string(finest_level) +
                      " only; refine the region around the bodies from the start, or set erf.moving_bodies.anchor_level to an existing level");
            }
            Abort("erf.moving_bodies: the bodies live on level " + std::to_string(m_anchor) + ", but the run has levels 0 to " +
                  std::to_string(finest_level) + " only now (did a regrid remove it?); the bodies would not be stepped");
        }
        return m_anchor;
    }

    std::vector<RealBox> support () const override { return m_support; }

    void initialize (const StructureInit& init) override
    {
        AMREX_ALWAYS_ASSERT(init.lev == m_anchor && !m_bodies);
        const bool restarting = !init.restart_chkfile.empty();
        // erf.coupling_type as SolverChoice reads it (a run with Anelastic and FullyCompressible levels,
        // which SolverChoice turns to OneWay, is refused by MovingBodies::create as not all anelastic)
        CouplingType coupling = CouplingType::TwoWay;
        ParmParse("erf").query_enum_case_insensitive("coupling_type", coupling);
        m_bodies = MovingBodies::create(std::move(m_in), m_max_level, !init.fully_compressible,
                                        coupling == CouplingType::TwoWay, init.fixed_dt, restarting, init.stop_time);

        const BoxArray ba = convert(init.xvel.boxArray(), IntVect::TheCellVector());
        const DistributionMapping& dm = init.xvel.DistributionMap();
        const MultiFab* zp   = heights(init.z_phys_nd, init.geom, ba, dm, init.xvel.nGrowVect());
        const MultiFab* detJ = jacobian(init.detJ_cc, ba, dm);
        m_bodies->set_ground(zp, init.geom, ba, dm, init.time);
        if (restarting) {
            m_bodies->read_checkpoint(init.restart_chkfile, init.time);
            if (m_anchor > 0 && coupling == CouplingType::TwoWay) {
                convert_earlier_coarse_source(init.restart_chkfile, ba, dm, detJ);
            }
        }
    }

    void advance (const StructureStep& step) override
    {
        // the actuator core places its kernels and samples at prob_lo + i dx with the volumes dx dy dz detJ,
        // with no map factors: checked every step, so also after a regrid
        if (!step.unit_map_factors) {
            Abort("erf.moving_bodies: the bodies' forces are spread and the velocities sampled without map factors, but level "
                  + std::to_string(step.lev) + " has a map factor other than 1; run the bodies on a mesh whose map factors are all 1");
        }
        const BoxArray& ba = step.cons.boxArray();
        const DistributionMapping& dm = step.cons.DistributionMap();
        const MultiFab* zp   = heights(step.z_phys_nd, step.geom, ba, dm, step.xvel.nGrowVect());
        const MultiFab* detJ = jacobian(step.detJ_cc, ba, dm);
        m_bodies->advance(step.lev, step.time, step.dt, step.cons, step.xvel, step.yvel, step.zvel, zp, detJ, step.geom);
        // ERF asks for the support only when a finer level exists; collective, and every rank calls advance()
        m_support.clear();
        if (step.finest_level > step.lev) { m_support = m_bodies->support_boxes(); }
    }

    void add_momentum_sources (int lev, MultiFab& xmom_src, MultiFab& ymom_src, MultiFab& zmom_src) const override
    {
        m_bodies->add_momentum_sources(lev, xmom_src, ymom_src, zmom_src);
    }

    void write_checkpoint (const std::string& checkpointname) const override
    {
        // under checkpointname/moving_bodies, where the bodies have always written. Writing flushes the
        // bodies' logs and summaries, which the const interface allows through the pointer: the coupled
        // state is left as it was
        m_bodies->write_checkpoint(checkpointname);
    }

    bool supports_restart () const override { return true; }

    void finalize () override { m_bodies->finalize(); }

private:
    /**
     * The heights the bodies sample and place their kernels with. On a uniform-dz mesh ERF hands the
     * model none; the bodies then get the flat heights prob_lo z + k dz that ERF's own z_phys_nd holds
     * there, so they take the same path on every mesh, as when ERF handed them z_phys_nd directly.
     */
    const MultiFab* heights (const MultiFab* z_phys_nd, const Geometry& geom, const BoxArray& ba,
                             const DistributionMapping& dm, const IntVect& ngrow)
    {
        if (z_phys_nd) { return z_phys_nd; }
        const BoxArray ba_nd = convert(ba, IntVect::TheNodeVector());
        if (!m_flat_z.isDefined() || m_flat_z.boxArray() != ba_nd || m_flat_z.DistributionMap() != dm) {
            m_flat_z.define(ba_nd, dm, 1, ngrow + IntVect(2));
            const Real dz = static_cast<Real>(geom.CellSize(2));
            const Real z_bot = static_cast<Real>(geom.ProbLo(2));
            for (MFIter mfi(m_flat_z); mfi.isValid(); ++mfi) {
                const Array4<Real> z = m_flat_z.array(mfi);
                ParallelFor(mfi.fabbox(), [=] AMREX_GPU_DEVICE (int i, int j, int k) { z(i, j, k) = z_bot + k * dz; });
            }
        }
        return &m_flat_z;
    }

    /** detJ_cc, or ones on a uniform-dz mesh (what ERF's detJ_cc holds there without EB). */
    const MultiFab* jacobian (const MultiFab* detJ_cc, const BoxArray& ba, const DistributionMapping& dm)
    {
        if (detJ_cc) { return detJ_cc; }
        if (!m_unit_j.isDefined() || m_unit_j.boxArray() != ba || m_unit_j.DistributionMap() != dm) {
            m_unit_j.define(ba, dm, 1, 1);
            m_unit_j.setVal(Real(1.0));
        }
        return &m_unit_j;
    }

    /**
     * A checkpoint of an earlier version keeps the anchor level's source where ERF does not read it
     * (moving_bodies/StructureCoarseSource, or the older face forces moving_bodies/force_{x,y,z}).
     * When <chk>/StructureCoarseSource is missing, the source is written there in ERF's layout, before
     * ERF reads it right after initialize() (ERF::read_structure_coarse_source_checkpoint). A checkpoint
     * that holds no source, or one the run cannot write into, gives the coarser levels an unforced first
     * step after the restart, and the log says so.
     */
    void convert_earlier_coarse_source (const std::string& chk, const BoxArray& ba, const DistributionMapping& dm,
                                        const MultiFab* detJ) const
    {
        const std::string dir = chk + "/StructureCoarseSource";
        int has_erf = 0;
        if (ParallelDescriptor::IOProcessor()) { has_erf = std::ifstream(dir + "/Level") ? 1 : 0; }
        ParallelDescriptor::Bcast(&has_erf, 1, ParallelDescriptor::IOProcessorNumber());
        if (has_erf != 0) { return; }
        const std::string unforced = " the levels below the anchor get the bodies' force from the anchor level's first step on "
                                     "(so their first step after the restart differs from a straight run's)\n";
        std::array<MultiFab,3> src;
        if (!m_bodies->read_earlier_coarse_source(chk, ba, dm, detJ, src)) {
            Print() << "Moving bodies: the checkpoint " << chk << " holds no anchor-level source;" << unforced;
            return;
        }
        int made = 0;
        if (ParallelDescriptor::IOProcessor()) { made = UtilCreateDirectory(dir, 0755) ? 1 : 0; }
        ParallelDescriptor::Bcast(&made, 1, ParallelDescriptor::IOProcessorNumber());
        if (made == 0) {
            Print() << "Moving bodies: cannot write " << dir << " (a read-only checkpoint?);" << unforced;
            return;
        }
        const char* face[3] = {"x_faces", "y_faces", "z_faces"};
        for (int d = 0; d < 3; ++d) { VisMF::Write(src[d], dir + "/" + face[d]); }
        // Level last: a run stopped before it leaves a directory a later restart converts again
        if (ParallelDescriptor::IOProcessor()) {
            std::ofstream level_file(dir + "/Level");
            level_file << m_anchor << "\n";
            if (!level_file) { Abort("structure model gale: cannot write " + dir + "/Level"); }
        }
        ParallelDescriptor::Barrier();
        Print() << "Structure model gale: wrote that source to " << dir << " in ERF's layout\n";
    }

    MovingBodiesInputs m_in;                 //!< read by the constructor, handed to MovingBodies::create
    int m_max_level{0};
    int m_anchor{0};
    std::unique_ptr<MovingBodies> m_bodies;  //!< created by initialize()
    std::vector<RealBox> m_support;          //!< as of the latest advance()
    MultiFab m_flat_z;                       //!< heights on a uniform-dz mesh
    MultiFab m_unit_j;                       //!< unit Jacobian on a uniform-dz mesh
};

} // namespace

ERF_REGISTER_STRUCTURE_MODEL(GaleTurbineModel, "gale")
