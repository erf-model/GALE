#include "ERF_TurbinePowerCurve.H"

#include <algorithm>
#include <cmath>
#include <sstream>

#include <AMReX.H>
#include <AMReX_ParallelDescriptor.H>
#include <AMReX_Vector.H>

using namespace amrex;

#ifndef GALE_TURBINE_DATA_DIR
#define GALE_TURBINE_DATA_DIR ""
#endif

namespace erf_actuator {

TurbinePowerCurve
TurbinePowerCurve::parse (const std::string& text, const std::string& where)
{
    TurbinePowerCurve c;
    bool have_d = false, have_hub = false, have_rated = false;
    std::istringstream in(text);
    std::string line;
    int lineno = 0;
    auto fail = [&] (const std::string& why) {
        Abort("Turbine table " + where + ", line " + std::to_string(lineno) + ": " + why);
    };
    while (std::getline(in, line)) {
        ++lineno;
        const auto first = line.find_first_not_of(" \t\r");
        if (first == std::string::npos || line[first] == '#') { continue; }
        std::istringstream ls(line);
        std::string head;
        ls >> head;
        std::string rest;
        if (head == "rotor_diameter" || head == "hub_height" || head == "rated_power") {
            if (!c.m_speed.empty()) { fail("the key " + head + " comes after the curve's rows"); }
            double v = 0.0;
            if (!(ls >> v) || (ls >> rest)) { fail(head + " must be followed by one number"); }
            if (!(v > 0.0) || !std::isfinite(v)) { fail(head + " must be positive"); }
            bool& seen = (head == "rotor_diameter") ? have_d : ((head == "hub_height") ? have_hub : have_rated);
            if (seen) { fail(head + " is given twice"); }
            seen = true;
            if (head == "rotor_diameter") { c.m_diameter = static_cast<Real>(v); }
            else if (head == "hub_height") { c.m_hub_height = static_cast<Real>(v); }
            else { c.m_rated_kw = static_cast<Real>(v); }
            continue;
        }
        // a row: wind speed, thrust coefficient, power (kW)
        std::istringstream rs(line);
        double u = 0.0, ct = 0.0, p = 0.0;
        if (!(rs >> u >> ct >> p) || (rs >> rest)) {
            fail("expected a key (rotor_diameter, hub_height, rated_power) or a row 'wind speed, Ct, power (kW)', not '" + line + "'");
        }
        if (!(u >= 0.0) || !std::isfinite(u)) { fail("the wind speed must be >= 0"); }
        if (!(ct >= 0.0 && ct <= max_ct)) { fail("the thrust coefficient must lie in [0, 2] (max_ct)"); }
        if (!(p >= 0.0) || !std::isfinite(p)) { fail("the power must be >= 0"); }
        if (!c.m_speed.empty() && !(u > c.m_speed.back())) { fail("the wind speeds must increase strictly"); }
        c.m_speed.push_back(static_cast<Real>(u));
        c.m_ct.push_back(static_cast<Real>(ct));
        c.m_power_kw.push_back(static_cast<Real>(p));
    }
    if (!have_d) { Abort("Turbine table " + where + " gives no rotor_diameter"); }
    if (!have_rated) { Abort("Turbine table " + where + " gives no rated_power"); }
    if (c.m_speed.size() < 2) { Abort("Turbine table " + where + " needs at least two rows (wind speed, Ct, power)"); }
    return c;
}

TurbinePowerCurve
TurbinePowerCurve::read_file (const std::string& file)
{
    Vector<char> buf;
    ParallelDescriptor::ReadAndBcastFile(file, buf, true);   // aborts when the file cannot be read
    return parse(std::string(buf.dataPtr()), file);
}

std::string
TurbinePowerCurve::table_file (const std::string& dir, const std::string& name)
{
    if (dir.empty()) { return name + ".txt"; }
    return (dir.back() == '/') ? dir + name + ".txt" : dir + "/" + name + ".txt";
}

std::string
TurbinePowerCurve::default_dir ()
{
    return GALE_TURBINE_DATA_DIR;
}

Real
TurbinePowerCurve::interpolate (const std::vector<Real>& v, Real u) const
{
    // outside [first, last] wind speed (and for a NaN speed): parked, no thrust and no power
    if (!(u >= m_speed.front() && u <= m_speed.back())) { return 0.0; }
    // the first row whose speed exceeds u; u == last falls on the last segment's end
    auto it = std::upper_bound(m_speed.begin(), m_speed.end(), u);
    const std::size_t j = (it == m_speed.end()) ? m_speed.size() - 1 : static_cast<std::size_t>(it - m_speed.begin());
    const std::size_t i = j - 1;
    const Real w = (u - m_speed[i]) / (m_speed[j] - m_speed[i]);
    return v[i] + w * (v[j] - v[i]);
}

} // namespace erf_actuator
