# The world: the lot, people on foot, and the routes round it

Christian's first play test (2026-10-11): "Players should be able to spawn into the lot which shows all the trucks … go up to a person or hit a key to buy the vehicles. This allows players to socialize in the lot and look in the distance to see other players." Until then the lot was a menu and a player was their truck from the first frame.

## The lot is a place, south of every route

`DdLot` is a slab with a fence round it, laid out in its own frame with -Z toward the mountain. From south to north: the spawn line, the showroom (a truck of every model in the catalogue on a plinth, its name and price over it, and a salesperson in the lot's amber beside it), the parking bays, and the north fence the roads leave through. `DdGame._build_lot` puts it under the middle of the routes' starts and `LOT_CLEARANCE` (170 m) south of the furthest south any road reaches, so the sea and the islands' slopes lie between; it is rebuilt with the routes, so another mountain moves it, and everybody on foot is put back on its spawn.

A server builds it too, undrawn: the slab and the fence are floors and walls, and the spots (spawn, bays, sellers) are where the world puts people and trucks and what it checks a use against. The showroom's trucks, people, signs and lamps are drawn only; each display truck is a frozen box so nobody walks through it.

## People walk on their own machine, and the world only refuses

A person joins on foot at the next spawn (`DdGame.join`, `_put_on_foot`); stand-ins never walk. On the player's machine `DdWalker` is a `CharacterBody3D` driven by dot-player-controller's third-person motor (`DotTpsController`, its camera off) and drawn as one of the family's people (`DotHumanoidFigure`, dot-player-char). The driving rows walk (W ahead, S back, A and D sideways), the handbrake's key jumps and Shift runs; the mouse looks round, so the pointer is captured on foot.

**Walking is the owner's, not predicted against the server.** This game predicts nothing (a truck is a rigid body, dot-vehicle's decision), so there is no rewind to keep a walker in step with, and a round trip on every step is the one latency a player feels at once. Nothing on foot can hurt anybody or win anything. So the owner moves, and says where they got to: offline straight to `DdGame.walk`, connected after the drive in every input packet (`DdEvents.write_walk`: a bit, three floats and ten bits of facing while on foot, one bit while driving). `walk` refuses a step longer than a run allows in one report (`WALK_STEP_MAX`, room for a few lost packets) and a place nobody on foot may be (`walkable`), and answers with where to stand (`walker_placed`, a PLACE to the owner), at most twice a second. Below `WALK_FLOOR` a walker is put back on the lot.

What everybody else sees of somebody on foot is `Driver.walker`, a plain node the world moves when it takes a step. The server replicates it (`DdWalkerNet`: position and a ten-bit facing, interpolated); each client hangs a person and a name tag under every walker but its own (`DdClient._present_walkers`), and the person animates from how far the node moved (`auto_animate`), so nothing about gait is sent. DRIVER carries `on_foot` and the walker's net id; the owner's own mirror is never drawn, because its body is.

## The camera on foot

One camera for walking, driving and the lot, so the settings' field of view and the rock's shake reach all three. On foot it sits behind and over the eyes, swept from the head by its own `DotCameraProbe` against the mountain's layer and layer 1 (a truck, a display or the fence is something to look past); F5 toggles first person where `mp_forceview` is 0, and 1 is first person only.
