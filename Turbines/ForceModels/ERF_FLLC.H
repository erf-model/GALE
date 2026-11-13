#ifndef ERF_FLLC_H
#define ERF_FLLC_H

#include <iosfwd>
#include <string>
#include <vector>

#include <AMReX_REAL.H>

namespace erf_actuator {

/**
 * Linear interpolation of 3-vectors given at the coordinates x_src (increasing) to the
 * coordinates x_dst; outside the source range the end values are held.
 */
void interpolate_along (const std::vector<amrex::Real>& x_src, const std::vector<amrex::Real>& v_src,
                        const std::vector<amrex::Real>& x_dst, std::vector<amrex::Real>& v_dst);

/**
 * Filtered lifting-line correction (Martinez-Tossas and Meneveau, 2019) for one blade of an
 * actuator line, in the generalized form for a chord that varies along the span (Martinez-Tossas,
 * Sakievich, Churchfield and Meneveau, Wind Energy 27:101, 2024, eq. 4: the optimal kernel width
 * stays inside the span integral), as Kynema's variable-chord operator implements it.
 *
 * An actuator line spread with a Gaussian of width epsilon sees, at its own points, a weaker
 * induced velocity than the vortex sheet of a real blade: the kernel is much wider than the
 * chord. The correction computes the velocity the trailing vorticity of the line's own lift
 * distribution induces at the line for the kernel actually used (u_les) and for the optimal
 * kernel epsilon_opt = eps_chord * chord (u_opt), and adds the relaxed difference to the
 * velocities OpenFAST is given:
 *
 *   G_i   = (F_i - v_i (F_i . v_i) / |v_i|^2) / dr_i        the lift force per unit span (per unit
 *                                                            density) at node i, F on the fluid
 *   u(r)  = 1 / (2 pi) sum_j G_j / |v_j| k(|r - r_j|, eps_j) dr_j
 *   k(r, eps) = exp(-r^2/eps^2) / eps^2 + (exp(-r^2/eps^2) - 1) / (2 r^2),  k(0) = 1 / (2 eps^2)
 *   du    = (1 - f) du + f (u_opt - u_les)
 *
 * The sum runs over a fine span grid with spacing epsilon_opt / eps_dr, onto which G / |v| and
 * epsilon_opt are interpolated, since the optimal kernel is far narrower than the node spacing.
 * The velocities are relative velocities (flow minus blade motion), the forces are those on
 * the fluid divided by the density, so G / |v| is minus the circulation along the lift
 * direction and du points against the lift: a downwash. The correction is a state (the
 * relaxation) and is checkpointed.
 */
class FLLC
{
public:
    /**
     * @param name the blade's name for messages
     * @param r span coordinate of the force nodes (m), root to tip, strictly increasing
     * @param chord chord at each force node (m)
     * @param eps_les the kernel width of the run (m)
     * @param eps_chord optimal kernel width in chords
     * @param eps_dr the optimal kernel width over the fine-grid spacing (spacing = epsilon_opt / eps_dr)
     * @param relax relaxation factor f in (0, 1]; the inputs keep it below max_stable_relax(eps_chord)
     */
    FLLC (std::string name, std::vector<amrex::Real> r, std::vector<amrex::Real> chord,
          amrex::Real eps_les, amrex::Real eps_chord, amrex::Real eps_dr, amrex::Real relax);

    /**
     * One relaxation step from the current loads and velocities at the force nodes.
     * @param force_over_rho 3*n forces on the fluid divided by the density (m^4/s^2)
     * @param vel_rel 3*n relative velocities at the force nodes (m/s)
     */
    void update (const std::vector<amrex::Real>& force_over_rho, const std::vector<amrex::Real>& vel_rel);

    /** The relaxed correction du at the force nodes (3*n, m/s). */
    const std::vector<amrex::Real>& correction () const { return m_du; }
    /** The latest unrelaxed u_opt - u_les at the force nodes (3*n, m/s). */
    const std::vector<amrex::Real>& target () const { return m_target; }
    amrex::Real max_correction () const;
    amrex::Real rms_correction () const;
    int num_points () const { return static_cast<int>(m_r.size()); }
    int num_fine_points () const { return static_cast<int>(m_rf.size()); }
    const std::vector<amrex::Real>& span () const { return m_r; }
    const std::vector<amrex::Real>& fine_span () const { return m_rf; }
    const std::string& name () const { return m_name; }

    /**
     * Write the span coordinates, chords and relaxed correction; read_state() restores them
     * (false when the stream has no block for this blade). The geometry is part of the state
     * because it is built from float node positions at whatever azimuth the object is built,
     * and a restart must continue with the straight run's grid, not rebuild it.
     */
    void write_state (std::ostream& out) const;
    bool read_state (std::istream& in);

    /** Kynema's kernel k(r, eps), the derivative of the filtered vortex kernel (1 - exp(-r^2/eps^2)) / r over 2. */
    static amrex::Real kernel (amrex::Real r, amrex::Real eps);

    /**
     * The induced velocity u(r_eval) = 1 / (2 pi) sum_j g_j k(|r_eval - r_j|, eps_j) dr_j of the
     * sources g_j = G_j / |v_j| (3*m) at r_src with widths dr_src and kernel widths eps_src.
     */
    static void induced_velocity (const std::vector<amrex::Real>& r_eval, const std::vector<amrex::Real>& r_src,
                                  const std::vector<amrex::Real>& g_src, const std::vector<amrex::Real>& dr_src,
                                  const std::vector<amrex::Real>& eps_src, std::vector<amrex::Real>& u);

    /**
     * The fine span grid from r.front() to r.back() with spacing epsilon_opt(r) / eps_dr. A step
     * that ends within 1e-6 of a step (or four roundings of Real at r.back()) short of r.back()
     * ends the grid at r.back(), so the last spacing is never a rounding residue.
     */
    static std::vector<amrex::Real> fine_grid (const std::vector<amrex::Real>& r, const std::vector<amrex::Real>& eps_opt,
                                               amrex::Real eps_dr);

    /**
     * max_kernel_transform * eps: the largest value of the kernel's Fourier transform
     * k^(q) = (pi |q| / 2) erfc(|q| eps / 2), reached at |q| eps / 2 = x*, the root of
     * erfc(x) = 2 x exp(-x^2) / sqrt(pi) (x* = 0.53160): pi x* erfc(x*).
     */
    static constexpr amrex::Real kernel_peak = amrex::Real(0.75516217769063950);

    /**
     * The lift slope the stability bound allows for, in units of 2 pi: tabulated airfoil slopes
     * near zero lift exceed the thin-airfoil 2 pi (the IEA 15 MW polars reach 1.37 times it).
     */
    static constexpr amrex::Real lift_slope_allowance = amrex::Real(1.4);

    /**
     * The largest relaxation factor for which the correction does not grow from one update to
     * the next: 4 eps_chord / (2 eps_chord + lift_slope_allowance * kernel_peak), that is
     * 4 eps_chord / (2 eps_chord + 1.057). It follows from the linearised loop in which the
     * correction changes the angle of attack and so the lift, with lift slope
     * lift_slope_allowance * 2 pi and a run kernel much wider than the optimal one. A lower lift
     * slope or a narrower run kernel only raises the bound. See ActuatorLine.rst.
     */
    static amrex::Real max_stable_relax (amrex::Real eps_chord);

    /**
     * The span each point stands for: half the distance between its two neighbours (the end
     * points: half the distance to their one neighbour), so the widths sum to the span.
     */
    static std::vector<amrex::Real> node_widths (const std::vector<amrex::Real>& r);

private:
    /** Derive the optimal widths, node widths and the fine grid from m_r and m_chord. */
    void build_grids (amrex::Real eps_chord, amrex::Real eps_dr);
    std::string m_name;
    amrex::Real m_eps_chord, m_eps_dr;
    std::vector<amrex::Real> m_r, m_chord, m_eps_opt, m_dr;   //!< at the force nodes
    std::vector<amrex::Real> m_rf, m_eps_opt_f, m_dr_f;        //!< the fine grid
    amrex::Real m_eps_les, m_relax;
    std::vector<amrex::Real> m_du, m_target;                   //!< 3*n at the force nodes
};

} // namespace erf_actuator

#endif
