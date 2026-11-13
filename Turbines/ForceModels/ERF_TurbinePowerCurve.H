#ifndef ERF_TURBINE_POWER_CURVE_H
#define ERF_TURBINE_POWER_CURVE_H

#include <string>
#include <vector>

#include <AMReX_REAL.H>

namespace erf_actuator {

/**
 * A turbine's thrust-coefficient and power curves, read from a table of GALE's turbine library
 * (Turbines/Data/PowerCurves/<name>.txt, written by make_power_curves.py). A ct_disk given
 * erf.moving_bodies.<name>.turbine takes its thrust coefficient from it at the sampled
 * free-stream speed, and its rotor diameter and (when the table has one) hub height.
 *
 * The table: lines starting with '#' are comments; the keys rotor_diameter (m), rated_power (kW)
 * and, optionally, hub_height (m), one per line as "<key> <value>"; then one row per wind speed:
 * wind speed (m/s), thrust coefficient (-), electrical power (kW), the wind speeds strictly
 * increasing. Between rows both curves are interpolated linearly; below the first and above the
 * last wind speed (cut-in and cut-out) both are zero.
 */
class TurbinePowerCurve
{
public:
    /** The largest thrust coefficient a table may hold. Published tables exceed 1 near cut-in
        (the NREL 5 MW table has 1.13 at 3 m/s). The parse message quotes the value 2. */
    static constexpr amrex::Real max_ct = amrex::Real(2.0);

    TurbinePowerCurve () = default;

    /**
     * Parse a table from its text. 'where' names it in the messages (a file name). Aborts on a
     * missing or repeated key, an unknown key, a row out of range or unordered, fewer than two rows.
     */
    static TurbinePowerCurve parse (const std::string& text, const std::string& where);

    /** Read and parse the table file (read by the I/O rank and broadcast; collective). */
    static TurbinePowerCurve read_file (const std::string& file);

    /** The table file of turbine name in directory dir: <dir>/<name>.txt. */
    static std::string table_file (const std::string& dir, const std::string& name);

    /** The folder of GALE's turbine library this build was configured with. */
    static std::string default_dir ();

    bool empty () const { return m_speed.empty(); }

    /** Thrust coefficient at wind speed u (m/s): linear between rows, 0 outside the table. */
    amrex::Real ct (amrex::Real u) const { return interpolate(m_ct, u); }
    /** Electrical power (W) at wind speed u (m/s): linear between rows, 0 outside the table. */
    amrex::Real power (amrex::Real u) const { return amrex::Real(1000.0) * interpolate(m_power_kw, u); }

    amrex::Real rotor_diameter () const { return m_diameter; }
    /** The table's hub height (m), or a negative number when it gives none (several are offered). */
    amrex::Real hub_height () const { return m_hub_height; }
    amrex::Real rated_power () const { return amrex::Real(1000.0) * m_rated_kw; }
    const std::vector<amrex::Real>& speeds () const { return m_speed; }

private:
    amrex::Real interpolate (const std::vector<amrex::Real>& v, amrex::Real u) const;

    std::vector<amrex::Real> m_speed, m_ct, m_power_kw;
    amrex::Real m_diameter{0.0};
    amrex::Real m_hub_height{-1.0};
    amrex::Real m_rated_kw{0.0};
};

} // namespace erf_actuator

#endif
