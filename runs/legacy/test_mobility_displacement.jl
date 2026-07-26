using DesJulia6gRupa
using DesJulia6gRupa.Types
import DesJulia6gRupa.Simulation as DSim

function dkm(a::GeoPoint, b::GeoPoint)
    R = 6371.0
    φ1 = deg2rad(a.lat); φ2 = deg2rad(b.lat)
    dφ = deg2rad(b.lat - a.lat); dλ = deg2rad(b.lon - a.lon)
    h = sin(dφ/2)^2 + cos(φ1)*cos(φ2)*sin(dλ/2)^2
    2R * asin(min(1.0, sqrt(h)))
end

start = GeoPoint(40.4168, -3.7038)  # Madrid
dt = 1.0; T = 600                   # 10 minutes

models = [
    ("RWP 50km/h jump20", RandomWaypoint(50.0, 0.0, 20.0)),
    ("RWP 5km/h jump2",   RandomWaypoint(5.0, 0.0, 2.0)),
    ("GM 80km/h a0.85",   GaussMarkov(80.0, 0.85, 5.0)),
]

for (name, model) in models
    loc = start
    st = MobilityState(start, 0.0, 0.0, 0.0, 0.0)
    pathlen = 0.0
    for _ in 1:T
        nl = DSim.step_position(model, loc, st, dt)
        pathlen += dkm(loc, nl)
        loc = nl
    end
    netdisp = dkm(start, loc)
    println(rpad(name, 22), " path=", round(pathlen, digits=2),
            "km  netdisp=", round(netdisp, digits=2), "km  over ", T*dt, "s")
end

# Expected path length at speed v over T*dt seconds: v(km/h) * (T*dt/3600) h
println("\nExpected path: 50km/h -> ", round(50*T*dt/3600, digits=2), "km, ",
        "5km/h -> ", round(5*T*dt/3600, digits=2), "km, ",
        "80km/h -> ", round(80*T*dt/3600, digits=2), "km")
