// Contracts of the turbine library (Turbines/Data/PowerCurves): a table's Ct and power are its rows at
// the rows' wind speeds, linear between them and zero outside them; a malformed table aborts with its
// line; a ct_disk given erf.moving_bodies.<name>.turbine takes its radius, hub height and Ct(U) from the
// table, and refuses a constant ct or a radius beside it.

#include <cmath>
#include <filesystem>
#include <map>
#include <string>
#include <vector>

#include <AMReX_ParmParse.H>
#include <AMReX_REAL.H>

#include <gtest/gtest.h>

#include "ERF_GTestThrowOnAbort.H"
#include "ERF_MovingBodiesInputs.H"
#include "ERF_PrescribedCtDisk.H"
#include "ERF_TurbinePowerCurve.H"

namespace {

using amrex::Real;
using erf_actuator::TurbinePowerCurve;
constexpr Real pi = 3.14159265358979323846;
// the table values are read as double and stored as Real; sums of a few terms
constexpr Real rel_tol = (sizeof(Real) == 8) ? Real(1.0e-12) : Real(2.0e-6);

const std::string small_table =
    "# a test table\n"
    "rotor_diameter 100\n"
    "hub_height 80\n"
    "rated_power 2000\n"
    "4 0.8 100\n"
    "  # a comment between rows\n"
    "8 0.7 1000\n"
    "12 0.3 2000\n";

std::string parse_error (const std::string& text)
{
    return erf_gtest::abort_message([&] () { TurbinePowerCurve::parse(text, "t.txt"); });
}

} // namespace

TEST(TurbinePowerCurve, InterpolatesLinearlyAndIsZeroOutsideTheTable)
{
    const TurbinePowerCurve c = TurbinePowerCurve::parse(small_table, "t.txt");
    EXPECT_EQ(c.rotor_diameter(), Real(100.0));
    EXPECT_EQ(c.hub_height(), Real(80.0));
    EXPECT_EQ(c.rated_power(), Real(2.0e6));
    ASSERT_EQ(c.speeds().size(), 3u);
    // at the rows: the rows (the first and the last speed included)
    EXPECT_EQ(c.ct(4.0), Real(0.8));
    EXPECT_EQ(c.ct(8.0), Real(0.7));
    EXPECT_EQ(c.ct(12.0), Real(0.3));
    EXPECT_EQ(c.power(12.0), Real(2.0e6));
    // between rows: linear, 6 m/s halfway from 4 to 8 and 11 m/s three quarters from 8 to 12
    EXPECT_NEAR(c.ct(6.0), 0.75, rel_tol);
    EXPECT_NEAR(c.power(6.0), 550.0e3, rel_tol * 550.0e3);
    EXPECT_NEAR(c.ct(11.0), 0.4, rel_tol);
    EXPECT_NEAR(c.power(11.0), 1750.0e3, rel_tol * 1750.0e3);
    // below cut-in, above cut-out, reversed flow and NaN: parked
    for (const Real u : {Real(3.999), Real(12.001), Real(0.0), Real(-5.0), Real(std::nan(""))}) {
        SCOPED_TRACE("u = " + std::to_string(u));
        EXPECT_EQ(c.ct(u), Real(0.0));
        EXPECT_EQ(c.power(u), Real(0.0));
    }
}

TEST(TurbinePowerCurve, TableWithoutHubHeightReportsNone)
{
    const TurbinePowerCurve c = TurbinePowerCurve::parse("rotor_diameter 82\nrated_power 1650\n3 0.979 0\n4 1.111 28\n", "t.txt");
    EXPECT_LT(c.hub_height(), Real(0.0));
    // a thrust coefficient above 1 (near cut-in, as published tables give) is accepted
    EXPECT_EQ(c.ct(4.0), Real(1.111));
}

TEST(TurbinePowerCurve, MalformedTablesAbortWithTheirLine)
{
    const std::string head = "rotor_diameter 100\nrated_power 2000\n";
    EXPECT_NE(parse_error(head + "4 0.8 100\n4 0.7 200\n").find("line 4: the wind speeds must increase strictly"), std::string::npos);
    EXPECT_NE(parse_error(head + "4 0.8 100\n3 0.7 200\n").find("increase strictly"), std::string::npos);
    EXPECT_NE(parse_error(head + "4 2.5 100\n8 0.7 200\n").find("line 3: the thrust coefficient must lie in [0, 2"), std::string::npos);
    EXPECT_NE(parse_error(head + "4 -0.1 100\n8 0.7 200\n").find("thrust coefficient"), std::string::npos);
    EXPECT_NE(parse_error(head + "-1 0.8 100\n8 0.7 200\n").find("wind speed must be >= 0"), std::string::npos);
    EXPECT_NE(parse_error(head + "4 0.8 -100\n8 0.7 200\n").find("power must be >= 0"), std::string::npos);
    EXPECT_NE(parse_error(head + "4 0.8\n8 0.7 200\n").find("line 3: expected a key"), std::string::npos);
    EXPECT_NE(parse_error(head + "4 0.8 100 7\n8 0.7 200\n").find("expected a key"), std::string::npos);
    EXPECT_NE(parse_error(head + "rotor_radius 50\n4 0.8 100\n8 0.7 200\n").find("expected a key"), std::string::npos);
    EXPECT_NE(parse_error(head + "4 0.8 100\nhub_height 80\n8 0.7 200\n").find("line 4: the key hub_height comes after"), std::string::npos);
    EXPECT_NE(parse_error(head + "rotor_diameter 90\n4 0.8 100\n8 0.7 200\n").find("rotor_diameter is given twice"), std::string::npos);
    EXPECT_NE(parse_error(head + "hub_height 0\n4 0.8 100\n8 0.7 200\n").find("hub_height must be positive"), std::string::npos);
    EXPECT_NE(parse_error(head + "hub_height 80 90\n4 0.8 100\n8 0.7 200\n").find("followed by one number"), std::string::npos);
    EXPECT_NE(parse_error(head + "4 0.8 100\n").find("at least two rows"), std::string::npos);
    EXPECT_NE(parse_error("rated_power 2000\n4 0.8 100\n8 0.7 200\n").find("gives no rotor_diameter"), std::string::npos);
    EXPECT_NE(parse_error("rotor_diameter 100\n4 0.8 100\n8 0.7 200\n").find("gives no rated_power"), std::string::npos);
    EXPECT_EQ(parse_error(small_table), "");
}

TEST(TurbinePowerCurve, ShippedNREL5MWTableHoldsThePublishedCurve)
{
    // NREL 5 MW reference turbine (Jonkman et al. 2009, NREL/TP-500-38060) as tabulated in the NREL
    // turbine-models archive: D = 126 m, hub 90 m, Ct 1.132 and 40.52 kW at 3 m/s, 5 MW at 25 m/s
    const TurbinePowerCurve c = TurbinePowerCurve::read_file(TurbinePowerCurve::table_file(TurbinePowerCurve::default_dir(), "NREL_5MW_126"));
    EXPECT_EQ(c.rotor_diameter(), Real(126.0));
    EXPECT_EQ(c.hub_height(), Real(90.0));
    EXPECT_EQ(c.rated_power(), Real(5.0e6));
    EXPECT_EQ(c.ct(3.0), Real(1.132034888));
    EXPECT_NEAR(c.power(3.0), 40.52e3, rel_tol * 40.52e3);
    EXPECT_NEAR(c.ct(7.05), 0.5 * (0.815371198 + 0.811614904), rel_tol);
    EXPECT_NEAR(c.power(25.0), 5000.04e3, rel_tol * 5.0e6);
    EXPECT_EQ(c.ct(25.5), Real(0.0));
    // every shipped table parses (the library's own checks), and keeps only rows with Ct > 0, so the
    // thrust has no ramp from zero below cut-in and no drop to zero between rows (make_power_curves.py)
    int ntables = 0;
    for (const auto& e : std::filesystem::directory_iterator(TurbinePowerCurve::default_dir())) {
        if (e.path().extension() != ".txt") { continue; }
        SCOPED_TRACE(e.path().string());
        const TurbinePowerCurve t = TurbinePowerCurve::read_file(e.path().string());
        for (const Real u : t.speeds()) { EXPECT_GT(t.ct(u), Real(0.0)) << "u = " << u; }
        ++ntables;
    }
    EXPECT_EQ(ntables, 44);
    // a missing table aborts naming the file
    const std::string msg = erf_gtest::abort_message([] () {
        TurbinePowerCurve::read_file(TurbinePowerCurve::table_file(TurbinePowerCurve::default_dir(), "No_Such_Turbine"));
    });
    EXPECT_NE(msg.find("No_Such_Turbine.txt"), std::string::npos);
}

TEST(TurbinePowerCurve, DiskTakesCtFromTheTableAtTheFreeStreamSpeed)
{
    MovingBodyInputs b;
    b.name = "DT";
    b.type = "ct_disk";
    b.base_pos = {{500.0, 400.0, 0.0}};
    b.curve = TurbinePowerCurve::parse(small_table, "t.txt");
    b.turbine = "small";
    b.rotor_radius = 50.0;
    b.hub_height = 80.0;
    b.num_points_r = 4;
    b.num_points_t = 8;
    b.sample_diameters_upstream = 1.0;
    b.air_density = 1.2;
    erf_actuator::PrescribedCtDisk d(b);
    ASSERT_TRUE(d.has_curve());
    const int n = d.num_points();
    for (const Real u : {Real(6.0), Real(11.0), Real(13.0)}) {
        SCOPED_TRACE("u = " + std::to_string(u));
        std::vector<Real> vs(3 * n, 0.0), vd(3 * n, 0.0);
        for (int k = 0; k < n; ++k) { vs[3*k] = u; vd[3*k] = 0.8 * u; }
        d.update(vs, vd);
        const Real ct = b.curve.ct(u);
        const Real T = 0.5 * 1.2 * ct * u * u * pi * 50.0 * 50.0;
        EXPECT_NEAR(d.ct(), ct, rel_tol);
        if (u == Real(6.0)) { EXPECT_NEAR(d.ct(), 0.75, rel_tol); }   // the table's row, not a constant
        // the thrust sums the disk's areas and speeds: 1e-9 relative in double, 2e-5 in single (as the disk tests)
        const Real thrust_tol = (sizeof(Real) == 8) ? Real(1.0e-9) : Real(2.0e-5);
        EXPECT_NEAR(d.thrust(), T, thrust_tol * (T + 1.0));
        EXPECT_NEAR(d.power_curve(), b.curve.power(u), rel_tol * (b.curve.power(u) + 1.0));
        Real row[7];
        d.log_row(0.0, true, row);
        EXPECT_EQ(row[5], d.ct());
        EXPECT_EQ(row[6], d.power_curve());
    }
    EXPECT_EQ(erf_actuator::PrescribedCtDisk::log_size(true), 7);
    EXPECT_EQ(erf_actuator::PrescribedCtDisk::log_size(false), 5);
    EXPECT_EQ(erf_actuator::PrescribedCtDisk::log_columns(false), "u_inf,u_disk,thrust,power,spread_thrust");
    EXPECT_EQ(erf_actuator::PrescribedCtDisk::log_columns(true), "u_inf,u_disk,thrust,power,spread_thrust,ct,power_curve");
}

TEST(TurbinePowerCurve, CtDiskInputsReadTheTurbineTable)
{
    {
        amrex::ParmParse pp("erf.moving_bodies");
        pp.addarr("bodies", std::vector<std::string>{"KA", "KB"});
    }
    {
        amrex::ParmParse pa("erf.moving_bodies.KA");
        pa.add("type", std::string("ct_disk"));
        pa.addarr("base_pos", std::vector<Real>{750.0, 600.0, 0.0});
        pa.add("turbine", std::string("NREL_5MW_126"));
        pa.add("epsilon", 3.0);
        // the V82 table offers several hub heights: this one is chosen
        amrex::ParmParse pb("erf.moving_bodies.KB");
        pb.add("type", std::string("ct_disk"));
        pb.addarr("base_pos", std::vector<Real>{1750.0, 600.0, 0.0});
        pb.add("turbine", std::string("Vestas_V82_1.65MW"));
        pb.add("hub_height", 78.0);
        pb.add("epsilon", 3.0);
    }
    const MovingBodiesInputs in = MovingBodiesInputs::read();
    ASSERT_EQ(in.bodies.size(), 2u);
    EXPECT_EQ(in.bodies[0].rotor_radius, Real(63.0));
    EXPECT_EQ(in.bodies[0].hub_height, Real(90.0));
    EXPECT_EQ(in.bodies[0].curve.ct(3.0), Real(1.132034888));
    EXPECT_EQ(in.bodies[1].rotor_radius, Real(41.0));
    EXPECT_EQ(in.bodies[1].hub_height, Real(78.0));
    // the restart record names the table and records ct = 0, so a restart switching to or from a constant ct is caught
    const auto rec = MovingBodiesInputs::restart_record(in.bodies[0]);
    bool named = false;
    for (const auto& kv : rec) { named = named || (kv.first == "turbine" && kv.second == "NREL_5MW_126"); }
    EXPECT_TRUE(named);
    std::map<std::string,std::string> chk_const;
    for (const auto& kv : rec) { if (kv.first != "turbine") { chk_const[kv.first] = kv.second; } }
    chk_const["ct"] = "0.75";   // a checkpoint of the same disk with a constant Ct
    std::string key, was, now;
    EXPECT_TRUE(MovingBodiesInputs::changed_record_entry(chk_const, rec, key, was, now));
    EXPECT_EQ(key, "ct");
}

TEST(TurbinePowerCurve, CtDiskInputsRefuseConflictingKeys)
{
    auto read_one = [] (const std::string& name, const std::vector<std::pair<std::string, std::string>>& keys) {
        {
            amrex::ParmParse pp("erf.moving_bodies");
            pp.addarr("bodies", std::vector<std::string>{name});
        }
        amrex::ParmParse pa("erf.moving_bodies." + name);
        pa.add("type", std::string("ct_disk"));
        pa.addarr("base_pos", std::vector<Real>{750.0, 600.0, 0.0});
        pa.add("epsilon", 3.0);
        for (const auto& kv : keys) { pa.add(kv.first.c_str(), kv.second); }
        return erf_gtest::abort_message([] () { MovingBodiesInputs::read(); });
    };
    EXPECT_NE(read_one("XA", {{"turbine", "NREL_5MW_126"}, {"ct", "0.75"}}).find("XA.ct and erf.moving_bodies.XA.turbine are both given"),
              std::string::npos);
    EXPECT_NE(read_one("XB", {{"turbine", "NREL_5MW_126"}, {"rotor_radius", "60"}}).find("XB.rotor_radius and"), std::string::npos);
    EXPECT_NE(read_one("XC", {{"turbine", "Vestas_V82_1.65MW"}}).find("XC.hub_height must be given"), std::string::npos);
    EXPECT_NE(read_one("XD", {{"turbine", "NREL_5MW_126"}, {"hub_height", "50"}}).find("XD.hub_height must exceed rotor_radius"),
              std::string::npos);
    EXPECT_NE(read_one("XE", {{"turbine", "No_Such_Turbine"}}).find("No_Such_Turbine.txt"), std::string::npos);
}
