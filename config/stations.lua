return {
    -- Prop used for crafting benches.
    model = `gr_prop_gr_bench_04b`,

    -- Benches spawn when you come within this many metres and despawn when you leave.
    renderDistance = 50.0,

    -- Props placed from the tablet spawn when you come within this many metres and despawn when you leave.
    propRenderDistance = 100.0,

    placement = {
        maxDistance = 8.0,    -- how far from you a bench can be placed
        rayLength = 25.0,     -- how far the camera aim ray reaches
        rotateStep = 5.0,     -- degrees per scroll tick
        fineRotateStep = 1.0, -- degrees per scroll tick while holding Shift
    },

    interaction = {
        distance = 1.6, -- how close you must be to a bench to use it
        control = 38,   -- key that opens the bench (38 = E), see https://docs.fivem.net/docs/game-references/controls/
        keyLabel = 'E', -- what the banner shows for that key
        target = false, -- true = open benches through ox_target instead of the key press (needs ox_target)
    },

    -- The banner drawn flat on the bench top. Offsets are relative to the bench (x = right, y = back, z = up).
    -- z is only a fallback: the banner snaps to the real top surface when the bench spawns.
    banner = {
        offset = vec3(0.0, 0.0, 0.85),
        width = 1.4,
        depth = 0.35,
        fadeDistance = 2.3, -- starts fading in at this distance, fully shown at interaction.distance
    },

    -- Where you stand and what you play while the menu is open. y is negative to stand in front of the bench.
    workstation = {
        standOffset = vec3(0.0, -1.0, 0.0),
        animDict = 'anim@amb@nightclub@lazlow@ig1_vip@',
        animClip = 'clubvip_base_laz',
    },

    -- Camera while the menu is open, relative to the bench.
    camera = {
        offset = vec3(0.0, -0.2, 1.85),
        target = vec3(0.0, 0.0, 0.9),
        fov = 50.0,
        transition = 600, -- ms
    },
}
